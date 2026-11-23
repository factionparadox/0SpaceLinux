project('zerospace-ring', 'cpp',
  version: '0.1.0',
  license: 'MIT',
  default_options: ['cpp_std=c++17', 'warning_level=2'])

wayfire = dependency('wayfire', version: '>=0.10.0')

add_project_arguments('-DWLR_USE_UNSTABLE', '-DWAYFIRE_PLUGIN', language: 'cpp')

shared_module('zerospace-ring', 'src/ring.cpp',
  dependencies: [wayfire],
  install: true,
  install_dir: wayfire.get_variable(pkgconfig: 'plugindir'))

install_data('metadata/zerospace-ring.xml',
  install_dir: wayfire.get_variable(pkgconfig: 'metadatadir'))
