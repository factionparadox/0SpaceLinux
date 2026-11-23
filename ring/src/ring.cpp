// 0-Space ring layout for Wayfire 0.10.
//
// A 3D carousel. Windows stand on a ring that runs back into the screen:
// the front window is full size and faces you; the others recede round the
// ring in perspective: smaller, higher and dimmer with depth, and squashed
// side-on round the sides of the ring.
// Rotating spins the carousel and brings the next window round to the front.
// The overview ("stalk-eye") lays every window out flat round an ellipse.
//
// Tiles are real windows at full size, shrunk with a 2D transformer, so apps
// never re-layout to a tiny size and clicks on a tile still land correctly.

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
#include <wayfire/signal-definitions.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/bindings.hpp>

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
    wf::option_wrapper_t<double> tile_width_opt{"zerospace-ring/tile_width"};
    wf::option_wrapper_t<double> overview_width_opt{"zerospace-ring/overview_width"};
    wf::option_wrapper_t<double> centre_height_opt{"zerospace-ring/centre_height"};
    wf::option_wrapper_t<int> gap_opt{"zerospace-ring/gap"};

    bool is_ringable(wayfire_toplevel_view view)
    {
        return view && view->is_mapped() && (view->role == wf::VIEW_ROLE_TOPLEVEL) &&
               !view->parent && (view->get_output() == output) && !view->minimized;
    }

    std::shared_ptr<wf::scene::view_2d_transformer_t> transformer_for(wayfire_toplevel_view view)
    {
        auto tmgr = view->get_transformed_node();
        auto tr   = tmgr->get_transformer<wf::scene::view_2d_transformer_t>(TRANSFORMER_NAME);
        if (!tr)
        {
            tr = std::make_shared<wf::scene::view_2d_transformer_t>(view);
            tmgr->add_transformer(tr, wf::TRANSFORMER_2D, TRANSFORMER_NAME);
        }

        return tr;
    }

    // Put a window at a screen position and size, faded to `alpha`. `turn`
    // (0 to 1) squashes it horizontally, as a window seen side-on would be.
    void place(wayfire_toplevel_view view, wf::geometry_t base, double scale,
        double centre_x, double centre_y, float alpha, double turn = 0.0)
    {
        if (alpha > 0.0f)
        {
            published_tiles.push_back({centre_x, centre_y, base.width * scale * (1.0 - turn),
                base.height * scale, name_of(view)});
        }

        view->damage();
        if (view->get_pending_geometry() != base)
        {
            view->set_geometry(base);
        }

        auto tr = transformer_for(view);
        tr->scale_x = scale * (1.0 - turn);
        tr->scale_y = scale;
        tr->translation_x = centre_x - (base.x + base.width / 2.0);
        tr->translation_y = centre_y - (base.y + base.height / 2.0);
        tr->alpha = alpha;
        view->damage();
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
                place(vis[i], centre, tile_scale, cx + rx * std::cos(a), cy + ry * std::sin(a), 1.0f);
            }

            publish(true, centre, cx, cy, rx, ry, false);
            return;
        }

        // The carousel: a ring on the floor, seen from slightly above. Angle 0
        // is the front; depth runs 0 (front) to 1 (back). Farther windows get
        // smaller and move towards the horizon and the middle, as in a real
        // perspective view.
        const size_t n = vis.size();
        const double step = (n > 0) ? 2.0 * M_PI / n : 0.0;
        const double front_y = centre.y + centre.height / 2.0;
        const double horizon = wa.y + wa.height * 0.08;
        const double radius_x = wa.width * 0.78;
        const double depth_k = 2.4;                 // how fast things shrink with distance
        const double min_alpha = 0.5;
        auto perspective = [&] (double depth) { return 1.0 / (1.0 + depth_k * depth); };

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
            const double scale = perspective(depth);
            const double x = cx + radius_x * std::sin(a) * scale;
            const double y = horizon + (front_y - horizon) * scale;
            // Windows round the sides are seen side-on: squash them, but never
            // so far that they disappear.
            const double turn = 0.5 * std::abs(std::sin(a));
            float alpha = (float)(1.0 - (1.0 - min_alpha) * depth);
            if (full && (i != 0))
            {
                alpha = 0.0f;
            }

            place(vis[i], centre, scale, x, y, alpha, turn);
            order.push_back({vis[i], depth});
        }

        // Stack back to front, so nearer windows cover farther ones.
        std::sort(order.begin(), order.end(), [] (const slot_t& a, const slot_t& b) { return a.depth > b.depth; });
        for (auto& o : order)
        {
            wf::view_bring_to_front(o.view);
        }

        // The floor ring the windows stand on, through their bases.
        const double s_back = perspective(1.0);
        const double s_side = perspective(0.5);
        const double front_base = front_y + centre.height / 2.0;
        const double back_base  = horizon + (front_y - horizon) * s_back + centre.height * s_back / 2.0;
        publish(true, centre, cx, (front_base + back_base) / 2.0, radius_x * s_side,
            (front_base - back_base) / 2.0, full);

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

        output->connect(&on_mapped);
        output->connect(&on_unmapped);
        output->connect(&on_minimized);
        output->connect(&on_workspace_changed);
        wf::get_core().connect(&on_focus);

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
    }
};

DECLARE_WAYFIRE_PLUGIN(wf::per_output_plugin_t<zerospace_ring_t>);
