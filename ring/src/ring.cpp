// 0-Space ring layout for Wayfire 0.10.
//
// A 3D carousel. Windows stand on a ring that runs back into the screen:
// the front window is full size and faces you; the others stand round the
// ring in real 3D space, seen in perspective from slightly above. Windows
// round the sides turn to face outwards, so they foreshorten like panels on
// a turntable, and the far side of the ring is smaller, higher and darker.
// Rotating spins the carousel and brings the next window round to the front.
// The overview ("stalk-eye") lays every window out flat round an ellipse.
//
// Tiles are real windows at full size, placed with Wayfire's 3D transformer,
// so apps never re-layout to a tiny size and clicks on a tile still land
// correctly (the transformer maps the pointer back through the projection).

#include <wayfire/plugin.hpp>
#include <wayfire/per-output-plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/core.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/workarea.hpp>
#include <wayfire/workspace-set.hpp>
#include <wayfire/geometry.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/view-helpers.hpp>
#include <chrono>
#include <wayfire/window-manager.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/bindings.hpp>
#include <set>

#include <wayland-server-core.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <cmath>
#include <vector>

namespace
{
const std::string TRANSFORMER_NAME = "zerospace-ring";
constexpr double SPIN_MS = 320.0;
constexpr double WIDTH_STEPS[] = {0.33, 0.50, 0.67, 1.00};
constexpr int WIDTH_STEP_COUNT = 4;
}

namespace
{
std::string json_escape(const std::string& in)
{
    std::string out;
    for (char c : in)
    {
        switch (c)
        {
          case '"':
            out += "\\\"";
            break;

          case '\\':
            out += "\\\\";
            break;

          default:
            if ((unsigned char)c >= 0x20)
            {
                out += c;
            }
        }
    }

    return out;
}

struct published_tile_t
{
    double x, y, w, h;
    std::string name;
};
}

class zerospace_ring_t : public wf::per_output_plugin_instance_t
{
    std::vector<published_tile_t> published_tiles;

    std::string name_of(wayfire_toplevel_view view)
    {
        std::string name = view->get_app_id();
        if (name.empty())
        {
            name = view->get_title();
        }

        return name;
    }

    // Shared ring order. On each workspace, the first of its windows holds
    // the centre and the rest follow clockwise round the orbit.
    std::vector<wayfire_toplevel_view> ring;
    bool overview = false;
    int width_step = 1; // 50% by default, leaving room for the orbit

    wf::option_wrapper_t<wf::activatorbinding_t> rotate_left_opt{"zerospace-ring/rotate_left"};
    wf::option_wrapper_t<wf::activatorbinding_t> rotate_right_opt{"zerospace-ring/rotate_right"};
    wf::option_wrapper_t<wf::activatorbinding_t> overview_opt{"zerospace-ring/overview"};
    wf::option_wrapper_t<wf::activatorbinding_t> cycle_width_opt{"zerospace-ring/cycle_width"};
    wf::option_wrapper_t<wf::activatorbinding_t> maximize_opt{"zerospace-ring/maximize"};
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_float_opt{"zerospace-ring/toggle_float"};
    wf::option_wrapper_t<wf::buttonbinding_t> drag_move_opt{"zerospace-ring/drag_move"};
    wf::option_wrapper_t<wf::buttonbinding_t> drag_resize_opt{"zerospace-ring/drag_resize"};
    wf::option_wrapper_t<double> tile_width_opt{"zerospace-ring/tile_width"};
    wf::option_wrapper_t<double> overview_width_opt{"zerospace-ring/overview_width"};
    wf::option_wrapper_t<double> centre_height_opt{"zerospace-ring/centre_height"};
    wf::option_wrapper_t<int> gap_opt{"zerospace-ring/gap"};
    wf::option_wrapper_t<double> ring_radius_opt{"zerospace-ring/ring_radius"};
    wf::option_wrapper_t<double> ring_tilt_opt{"zerospace-ring/ring_tilt"};
    wf::option_wrapper_t<double> ring_turn_opt{"zerospace-ring/ring_turn"};

    // Floating windows are left where you put them, above the carousel.
    std::set<wayfire_toplevel_view> floating;

    bool is_ringable(wayfire_toplevel_view view)
    {
        return view && view->is_mapped() && (view->role == wf::VIEW_ROLE_TOPLEVEL) &&
               !view->parent && (view->get_output() == output) && !view->minimized &&
               !floating.count(view);
    }

    std::shared_ptr<wf::scene::view_3d_transformer_t> transformer_for(wayfire_toplevel_view view)
    {
        auto tmgr = view->get_transformed_node();
        auto tr   = tmgr->get_transformer<wf::scene::view_3d_transformer_t>(TRANSFORMER_NAME);
        if (!tr)
        {
            tr = std::make_shared<wf::scene::view_3d_transformer_t>(view);
            tmgr->add_transformer(tr, wf::TRANSFORMER_3D, TRANSFORMER_NAME);
        }

        return tr;
    }

    // The carousel's camera. Wayfire's own default lens is very long (22.5°),
    // which flattens depth; a wider one gives the ring real perspective. The
    // camera sits where a point at depth 0 keeps its exact pixel size, so the
    // front window is drawn 1:1.
    static constexpr float CAMERA_FOV = glm::radians(38.0f);
    static glm::mat4 camera()
    {
        const float dist = 1.0f / std::tan(CAMERA_FOV / 2.0f);
        return glm::perspective(CAMERA_FOV, 1.0f, 0.1f, 100.0f) *
               glm::lookAt(glm::vec3(0, 0, dist), glm::vec3(0, 0, 0), glm::vec3(0, 1, 0));
    }

    // Wayfire measures depth in units of half the window's larger side. The
    // carousel works in pixels, so `ref` is the shared pixel scale for depth.
    double depth_ref = 1.0;

    void prepare(wayfire_toplevel_view view, wf::geometry_t base)
    {
        view->damage();
        if (view->get_pending_geometry() != base)
        {
            view->set_geometry(base);
        }
    }

    void publish_tile(wayfire_toplevel_view view,
        const std::shared_ptr<wf::scene::view_3d_transformer_t>& tr, float alpha)
    {
        if (alpha <= 0.0f)
        {
            return;
        }

        const auto b = tr->get_bounding_box();
        published_tiles.push_back({b.x + b.width / 2.0, b.y + b.height / 2.0,
            (double)b.width, (double)b.height, name_of(view)});
    }

    // Flat placement (the overview): a window at a screen position, scaled,
    // facing straight out of the screen.
    void place_flat(wayfire_toplevel_view view, wf::geometry_t base, double scale,
        double centre_x, double centre_y, float alpha)
    {
        prepare(view, base);
        auto tr = transformer_for(view);
        tr->view_proj   = wf::scene::view_3d_transformer_t::default_proj_matrix() *
            wf::scene::view_3d_transformer_t::default_view_matrix();
        tr->rotation    = glm::mat4(1.0);
        tr->scaling     = glm::scale(glm::mat4(1.0), glm::vec3(scale, scale, 1.0));
        // Wayfire's 3D space has y pointing up.
        tr->translation = glm::translate(glm::mat4(1.0), glm::vec3(
            centre_x - (base.x + base.width / 2.0), -(centre_y - (base.y + base.height / 2.0)), 0.0));
        tr->color = {1.0f, 1.0f, 1.0f, alpha};
        view->damage();
        publish_tile(view, tr, alpha);
    }

    // 3D placement (the carousel): `world` moves and turns the window in
    // pixel space round its own centre, which is the front window's centre.
    // `dim` darkens it, `alpha` fades it.
    void place_3d(wayfire_toplevel_view view, wf::geometry_t base, const glm::mat4& world,
        float dim, float alpha)
    {
        prepare(view, base);
        auto tr = transformer_for(view);

        // Undo Wayfire's per-window depth scale, so every window shares one
        // depth scale and the ring stays round whatever size a window is.
        const auto bbox = tr->get_children_bounding_box();
        const double own = std::max(1.0, (double)std::max(bbox.width, bbox.height));
        const float k = (float)(own / depth_ref);

        tr->view_proj   = camera();
        tr->rotation    = glm::scale(glm::mat4(1.0), glm::vec3(1.0f, 1.0f, k)) * world;
        tr->scaling     = glm::mat4(1.0);
        tr->translation = glm::mat4(1.0);
        tr->color = {dim, dim, dim, alpha};
        view->damage();
        publish_tile(view, tr, alpha);
    }

    // Where a point in the carousel's pixel space lands on screen, relative
    // to the front window's centre (y down, as on screen).
    wf::pointf_t project(const glm::vec3& p)
    {
        const glm::mat4 depth = glm::scale(glm::mat4(1.0), glm::vec3(1.0f, 1.0f, (float)(2.0 / depth_ref)));
        glm::vec4 v = camera() * depth * glm::vec4(p, 1.0f);
        if (std::abs(v.w) < 1e-6)
        {
            return {0, 0};
        }

        return {v.x / v.w, -v.y / v.w};
    }

    // Only windows on the current workspace take part in the ring; each
    // workspace has its own centre and orbit, in the shared ring order.
    std::vector<size_t> visible_indices()
    {
        std::vector<size_t> idx;
        auto wset = output->wset();
        const auto ws = wset->get_current_workspace();
        for (size_t i = 0; i < ring.size(); i++)
        {
            if (wset->get_view_main_workspace(ring[i]) == ws)
            {
                idx.push_back(i);
            }
        }

        return idx;
    }

    std::vector<wayfire_toplevel_view> visible_views(const std::vector<size_t>& idx)
    {
        std::vector<wayfire_toplevel_view> views;
        for (auto i : idx)
        {
            views.push_back(ring[i]);
        }

        return views;
    }

    void write_back(const std::vector<wayfire_toplevel_view>& views, const std::vector<size_t>& idx)
    {
        for (size_t k = 0; k < idx.size(); k++)
        {
            ring[idx[k]] = views[k];
        }
    }

    // Workstations (1-based) that hold at least one window.
    std::string occupied_list()
    {
        std::set<int> used;
        auto wset = output->wset();
        for (auto& view : wset->get_views(wf::WSET_MAPPED_ONLY))
        {
            if (view->role == wf::VIEW_ROLE_TOPLEVEL)
            {
                used.insert(wset->get_view_main_workspace(view).x + 1);
            }
        }

        std::string list;
        for (int ws : used)
        {
            list += (list.empty() ? "" : ",") + std::to_string(ws);
        }

        return list;
    }

    // Orders from the shell, one per line, through a pipe beside the JSON:
    //   workspace N   go to workstation N
    std::string control_path;
    int control_fd = -1;
    wl_event_source *control_source = nullptr;
    std::string control_buffer;

    static int on_control_readable(int fd, uint32_t, void *data)
    {
        auto self = static_cast<zerospace_ring_t*>(data);
        char buf[256];
        ssize_t n;
        while ((n = read(fd, buf, sizeof(buf))) > 0)
        {
            self->control_buffer.append(buf, n);
        }

        size_t nl;
        while ((nl = self->control_buffer.find('\n')) != std::string::npos)
        {
            self->run_order(self->control_buffer.substr(0, nl));
            self->control_buffer.erase(0, nl + 1);
        }

        return 0;
    }

    void run_order(const std::string& line)
    {
        int n = 0;
        if (std::sscanf(line.c_str(), "workspace %d", &n) == 1)
        {
            auto wset = output->wset();
            const auto grid = wset->get_workspace_grid_size();
            if ((n >= 1) && (n <= grid.width))
            {
                wset->request_workspace({n - 1, wset->get_current_workspace().y});
            }
        }
    }

    void open_control()
    {
        const char *runtime = std::getenv("XDG_RUNTIME_DIR");
        if (!runtime)
        {
            return;
        }

        control_path = std::string(runtime) + "/0space-ring-" + output->to_string() + ".ctl";
        ::unlink(control_path.c_str());
        if (::mkfifo(control_path.c_str(), 0600) != 0)
        {
            return;
        }

        // Read-write, so the pipe never reports end-of-file between writers.
        control_fd = ::open(control_path.c_str(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
        if (control_fd >= 0)
        {
            control_source = wl_event_loop_add_fd(wf::get_core().ev_loop, control_fd,
                WL_EVENT_READABLE, on_control_readable, this);
        }
    }

    void close_control()
    {
        if (control_source)
        {
            wl_event_source_remove(control_source);
            control_source = nullptr;
        }

        if (control_fd >= 0)
        {
            ::close(control_fd);
            control_fd = -1;
        }

        if (!control_path.empty())
        {
            ::unlink(control_path.c_str());
        }
    }

    // Tell the shell where the ring is, so it can draw the orbit and the
    // frame round the centre. Written atomically to $XDG_RUNTIME_DIR.
    void publish(bool active, wf::geometry_t centre, double cx, double cy, double rx, double ry,
        bool full)
    {
        const char *runtime = std::getenv("XDG_RUNTIME_DIR");
        if (!runtime)
        {
            return;
        }

        const std::string path = std::string(runtime) + "/0space-ring-" + output->to_string() + ".json";
        const std::string tmp  = path + ".tmp";
        {
            std::ofstream out(tmp, std::ios::trunc);
            if (!out)
            {
                return;
            }

            out << "{\"active\":" << (active ? "true" : "false")
                << ",\"overview\":" << (overview ? "true" : "false")
                << ",\"full\":" << (full ? "true" : "false")
                << ",\"centre\":[" << centre.x << "," << centre.y << "," << centre.width << "," << centre.height << "]"
                << ",\"orbit\":[" << cx << "," << cy << "," << rx << "," << ry << "]"
                << ",\"workspace\":" << output->wset()->get_current_workspace().x + 1
                << ",\"workspaces\":" << output->wset()->get_workspace_grid_size().width
                << ",\"occupied\":[" << occupied_list() << "]"
                << ",\"tiles\":[";
            for (size_t i = 0; i < published_tiles.size(); i++)
            {
                const auto& t = published_tiles[i];
                out << (i ? "," : "") << "{\"x\":" << t.x << ",\"y\":" << t.y << ",\"w\":" << t.w
                    << ",\"h\":" << t.h << ",\"name\":\"" << json_escape(t.name) << "\"}";
            }

            out << "]}\n";
        }

        std::rename(tmp.c_str(), path.c_str());
    }

    // Spin animation: the carousel is drawn `spin_offset` radians away from
    // rest, easing back to zero.
    double spin_from = 0.0;
    double spin_offset = 0.0;
    std::chrono::steady_clock::time_point spin_start;
    bool spinning = false;

    wf::effect_hook_t on_frame = [=] ()
    {
        const double ms = std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - spin_start).count();
        const double t = std::min(1.0, ms / SPIN_MS);
        const double ease = 1.0 - std::pow(1.0 - t, 3.0);
        spin_offset = spin_from * (1.0 - ease);
        arrange(false);
        if (t >= 1.0)
        {
            spin_offset = 0.0;
            spinning = false;
            output->render->rem_effect(&on_frame);
            arrange(true);
        } else
        {
            output->render->schedule_redraw();
        }
    };

    void spin(double from)
    {
        spin_from = from;
        spin_offset = from;
        spin_start = std::chrono::steady_clock::now();
        if (!spinning)
        {
            spinning = true;
            output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
        }

        output->render->schedule_redraw();
    }

    void layout()
    {
        arrange(true);
    }

    void arrange(bool settle)
    {
        published_tiles.clear();
        const auto idx = visible_indices();
        const auto vis = visible_views(idx);
        if (vis.empty())
        {
            publish(false, {0, 0, 0, 0}, 0, 0, 0, 0, false);
            raise_floating();
            return;
        }

        const auto wa = output->workarea->get_workarea();
        const int gap = gap_opt;
        const double cx = wa.x + wa.width / 2.0;
        const double frac = WIDTH_STEPS[width_step];
        const bool full = !overview && (frac >= 1.0);

        // The front window's real size; every window shares it, and the
        // carousel scales the others down by depth.
        wf::geometry_t centre;
        if (full)
        {
            centre = {wa.x + gap, wa.y + gap, wa.width - 2 * gap, wa.height - 2 * gap};
        } else
        {
            centre.width  = std::max(1, (int)(wa.width * frac) - 2 * gap);
            centre.height = std::max(1, (int)(wa.height * (double)centre_height_opt));
            centre.x = (int)(cx - centre.width / 2.0);
            centre.y = (int)(wa.y + wa.height * 0.62 - centre.height / 2.0);
        }

        if (overview)
        {
            // Stalk-eye view: everything flat and evenly round an ellipse.
            const double cy = wa.y + wa.height / 2.0;
            const double tile_scale = std::min(1.0, wa.width * (double)overview_width_opt / std::max(1, centre.width));
            const double rx = std::max(0.0, wa.width / 2.0 - centre.width * tile_scale / 2.0 - gap);
            const double ry = std::max(0.0, wa.height / 2.0 - centre.height * tile_scale / 2.0 - gap);
            const size_t n = vis.size();
            for (size_t i = 0; i < n; i++)
            {
                const double a = (-90.0 + i * 360.0 / n) * M_PI / 180.0;
                place_flat(vis[i], centre, tile_scale, cx + rx * std::cos(a), cy + ry * std::sin(a), 1.0f);
            }

            publish(true, centre, cx, cy, rx, ry, false);
            return;
        }

        // The carousel: a real ring in 3D space, seen from slightly above.
        // The front window sits at the origin (its own centre), facing you at
        // full size. The ring runs back into the screen from there; angle 0
        // is the front, and depth runs 0 (front) to 1 (back).
        const size_t n = vis.size();
        const double step = (n > 0) ? 2.0 * M_PI / n : 0.0;
        const double front_cx = centre.x + centre.width / 2.0;
        const double front_cy = centre.y + centre.height / 2.0;
        depth_ref = std::max(1, std::max(centre.width, centre.height));

        const float radius = (float)(wa.width * (double)ring_radius_opt);
        const glm::mat4 tilt = glm::rotate(glm::mat4(1.0f),
            glm::radians((float)(double)ring_tilt_opt), glm::vec3(1.0f, 0.0f, 0.0f));
        // Where a spot on the ring floor ends up, once the ring is tilted.
        auto on_ring = [&] (double a, float y)
        {
            glm::vec4 p = tilt * glm::vec4(radius * (float)std::sin(a), 0.0f,
                -radius + radius * (float)std::cos(a), 1.0f);
            return glm::vec3(p.x, p.y + y, p.z);
        };

        struct slot_t
        {
            wayfire_toplevel_view view;
            double depth;
        };
        std::vector<slot_t> order;

        for (size_t i = 0; i < n; i++)
        {
            const double a = i * step + spin_offset;
            const double depth = (1.0 - std::cos(a)) / 2.0;

            // Each window turns to face outwards from the ring as it goes
            // round, like a panel on a turntable, so the side windows are
            // seen at an angle with their far edge shorter. They turn back to
            // face you round the back, so you never see a window from behind.
            const float yaw = (float)((double)ring_turn_opt * std::sin(a));
            const glm::mat4 world =
                glm::translate(glm::mat4(1.0f), on_ring(a, 0.0f)) *
                glm::rotate(glm::mat4(1.0f), yaw, glm::vec3(0.0f, 1.0f, 0.0f));

            // Farther windows are darker and a little see-through.
            float dim   = (float)(1.0 - 0.55 * depth);
            float alpha = (float)(1.0 - 0.25 * depth);
            if (full && (i != 0))
            {
                alpha = 0.0f;
            }

            place_3d(vis[i], centre, world, dim, alpha);
            order.push_back({vis[i], depth});
        }

        // Stack back to front, so nearer windows cover farther ones.
        std::sort(order.begin(), order.end(), [] (const slot_t& a, const slot_t& b) { return a.depth > b.depth; });
        for (auto& o : order)
        {
            wf::view_bring_to_front(o.view);
        }

        raise_floating();

        // The floor ring the windows stand on, through their bases: project
        // its front, back and sides, and hand the shell the ellipse they make.
        const float base_y = -centre.height / 2.0f;
        const auto f = project(on_ring(0.0, base_y));
        const auto b = project(on_ring(M_PI, base_y));
        const auto l = project(on_ring(-M_PI / 2.0, base_y));
        const auto r = project(on_ring(M_PI / 2.0, base_y));
        publish(true, centre, front_cx + (l.x + r.x) / 2.0, front_cy + (f.y + b.y) / 2.0,
            std::abs(r.x - l.x) / 2.0, std::abs(f.y - b.y) / 2.0, full);

        if (settle)
        {
            wf::get_core().default_wm->focus_raise_view(vis[0]);
        }
    }

    void bring_to_centre(wayfire_toplevel_view view)
    {
        const auto idx = visible_indices();
        auto vis = visible_views(idx);
        auto it  = std::find(vis.begin(), vis.end(), view);
        if ((it == vis.end()) || (it == vis.begin()))
        {
            return;
        }

        // Rotate rather than swap, so the orbit keeps its order, and spin the
        // carousel round from where the window was.
        const long k = it - vis.begin();
        const long n = (long)vis.size();
        const long shortest = (k <= n / 2) ? k : k - n;
        std::rotate(vis.begin(), it, vis.end());
        write_back(vis, idx);
        if (!overview && (n > 1))
        {
            spin(shortest * 2.0 * M_PI / n);
        }
    }

    void rotate(int direction)
    {
        const auto idx = visible_indices();
        auto vis = visible_views(idx);
        if (vis.size() < 2)
        {
            return;
        }

        if (direction > 0)
        {
            std::rotate(vis.begin(), vis.begin() + 1, vis.end());
        } else
        {
            std::rotate(vis.rbegin(), vis.rbegin() + 1, vis.rend());
        }

        write_back(vis, idx);
        if (!overview)
        {
            const double step = 2.0 * M_PI / vis.size();
            spin(direction > 0 ? step : -step);
        } else
        {
            layout();
        }
    }

    void raise_floating()
    {
        for (auto& view : floating)
        {
            if (view->get_output() == output)
            {
                wf::view_bring_to_front(view);
            }
        }
    }

    // Take a window out of the carousel. It stays where it was drawn, at its
    // real size, and floats above the others.
    void float_view(wayfire_toplevel_view view)
    {
        if (!view || floating.count(view))
        {
            return;
        }

        const bool ringed = std::find(ring.begin(), ring.end(), view) != ring.end();
        const wf::geometry_t drawn = view->get_bounding_box();
        drop(view);
        floating.insert(view);
        if (ringed)
        {
            auto g = view->get_geometry();
            view->move(drawn.x + drawn.width / 2 - g.width / 2, drawn.y + drawn.height / 2 - g.height / 2);
        }

        wf::view_bring_to_front(view);
        layout();
    }

    // Back into the carousel, at the centre.
    void sink_view(wayfire_toplevel_view view)
    {
        if (!floating.erase(view))
        {
            return;
        }

        if (is_ringable(view))
        {
            ring.insert(ring.begin(), view);
        }

        overview = false;
        layout();
    }

    void drop(wayfire_toplevel_view view)
    {
        auto it = std::find(ring.begin(), ring.end(), view);
        if (it == ring.end())
        {
            return;
        }

        view->get_transformed_node()->rem_transformer(TRANSFORMER_NAME);
        ring.erase(it);
    }

    wf::activator_callback on_rotate_left = [=] (const wf::activator_data_t&)
    {
        rotate(-1);
        return true;
    };

    wf::activator_callback on_rotate_right = [=] (const wf::activator_data_t&)
    {
        rotate(1);
        return true;
    };

    wf::activator_callback on_overview = [=] (const wf::activator_data_t&)
    {
        overview = !overview;
        layout();
        return true;
    };

    wf::activator_callback on_cycle_width = [=] (const wf::activator_data_t&)
    {
        width_step = (width_step + 1) % WIDTH_STEP_COUNT;
        layout();
        return true;
    };

    wf::activator_callback on_maximize = [=] (const wf::activator_data_t&)
    {
        width_step = (width_step == WIDTH_STEP_COUNT - 1) ? 1 : WIDTH_STEP_COUNT - 1;
        layout();
        return true;
    };

    wf::activator_callback on_toggle_float = [=] (const wf::activator_data_t&)
    {
        auto view = wf::toplevel_cast(wf::get_active_view_for_output(output));
        if (!view)
        {
            return false;
        }

        if (floating.count(view))
        {
            sink_view(view);
        } else
        {
            float_view(view);
        }

        return true;
    };

    // Super+drag: a carousel window floats where it is, then Wayfire's own
    // move and resize take over the drag.
    wayfire_toplevel_view view_under_cursor()
    {
        auto view = wf::toplevel_cast(wf::get_core().get_cursor_focus_view());
        return (view && (view->get_output() == output) &&
            (view->role == wf::VIEW_ROLE_TOPLEVEL)) ? view : nullptr;
    }

    wf::button_callback on_drag_move = [=] (const wf::buttonbinding_t&)
    {
        auto view = view_under_cursor();
        if (!view)
        {
            return false;
        }

        float_view(view);
        wf::view_move_request_signal req;
        req.view = view;
        output->emit(&req);
        return true;
    };

    wf::button_callback on_drag_resize = [=] (const wf::buttonbinding_t&)
    {
        auto view = view_under_cursor();
        if (!view)
        {
            return false;
        }

        float_view(view);
        // Resize from the corner nearest the pointer.
        const auto g = view->get_geometry();
        const auto p = wf::get_core().get_cursor_position();
        constexpr uint32_t TOP = 1, BOTTOM = 2, LEFT = 4, RIGHT = 8;
        wf::view_resize_request_signal req;
        req.view  = view;
        req.edges = ((p.x < g.x + g.width / 2.0) ? LEFT : RIGHT) | ((p.y < g.y + g.height / 2.0) ? TOP : BOTTOM);
        output->emit(&req);
        return true;
    };

    // A newly opened window takes the centre; the old centre joins the orbit.
    wf::signal::connection_t<wf::view_mapped_signal> on_mapped = [=] (wf::view_mapped_signal *ev)
    {
        auto view = wf::toplevel_cast(ev->view);
        if (!is_ringable(view) || (std::find(ring.begin(), ring.end(), view) != ring.end()))
        {
            return;
        }

        ring.insert(ring.begin(), view);
        overview = false;
        layout();
    };

    wf::signal::connection_t<wf::view_unmapped_signal> on_unmapped = [=] (wf::view_unmapped_signal *ev)
    {
        auto view = wf::toplevel_cast(ev->view);
        floating.erase(view);
        if (view && (std::find(ring.begin(), ring.end(), view) != ring.end()))
        {
            drop(view);
            layout();
        }
    };

    wf::signal::connection_t<wf::view_minimized_signal> on_minimized = [=] (wf::view_minimized_signal *ev)
    {
        if (ev->view->minimized)
        {
            drop(ev->view);
        } else if (is_ringable(ev->view))
        {
            ring.insert(ring.begin(), ev->view);
        }

        layout();
    };

    // Clicking a tile (or anything else that moves focus) brings that window
    // to the centre. In the overview, choosing a window also closes it.
    wf::signal::connection_t<wf::keyboard_focus_changed_signal> on_focus =
        [=] (wf::keyboard_focus_changed_signal *ev)
    {
        auto view = wf::toplevel_cast(wf::node_to_view(ev->new_focus));
        if (!view || (std::find(ring.begin(), ring.end(), view) == ring.end()))
        {
            return;
        }

        const auto idx = visible_indices();
        if (!overview && !idx.empty() && (view == ring[idx[0]]))
        {
            return;
        }

        bring_to_centre(view);
        overview = false;
        layout();
    };

    wf::signal::connection_t<wf::workspace_changed_signal> on_workspace_changed =
        [=] (wf::workspace_changed_signal*)
    {
        overview = false;
        layout();
    };

  public:
    void init() override
    {
        output->add_activator(rotate_left_opt, &on_rotate_left);
        output->add_activator(rotate_right_opt, &on_rotate_right);
        output->add_activator(overview_opt, &on_overview);
        output->add_activator(cycle_width_opt, &on_cycle_width);
        output->add_activator(maximize_opt, &on_maximize);
        output->add_activator(toggle_float_opt, &on_toggle_float);
        output->add_button(drag_move_opt, &on_drag_move);
        output->add_button(drag_resize_opt, &on_drag_resize);

        output->connect(&on_mapped);
        output->connect(&on_unmapped);
        output->connect(&on_minimized);
        output->connect(&on_workspace_changed);
        wf::get_core().connect(&on_focus);
        open_control();

        // Adopt windows that were already open when the plugin loaded.
        for (auto& view : output->wset()->get_views(wf::WSET_MAPPED_ONLY | wf::WSET_EXCLUDE_MINIMIZED))
        {
            if (is_ringable(view))
            {
                ring.push_back(view);
            }
        }

        layout();
    }

    void fini() override
    {
        output->rem_binding(&on_rotate_left);
        output->rem_binding(&on_rotate_right);
        output->rem_binding(&on_overview);
        output->rem_binding(&on_cycle_width);
        output->rem_binding(&on_maximize);
        output->rem_binding(&on_toggle_float);
        output->rem_binding(&on_drag_move);
        output->rem_binding(&on_drag_resize);

        for (auto& view : ring)
        {
            view->damage();
            view->get_transformed_node()->rem_transformer(TRANSFORMER_NAME);
            view->damage();
        }

        if (spinning)
        {
            output->render->rem_effect(&on_frame);
        }

        ring.clear();
        floating.clear();
        close_control();
    }
};

DECLARE_WAYFIRE_PLUGIN(wf::per_output_plugin_t<zerospace_ring_t>);
