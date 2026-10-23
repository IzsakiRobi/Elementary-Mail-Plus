icon_sizes = ['16', '24', '32', '48', '64', '128']

foreach i : icon_sizes
    install_data(
        join_paths('icons', i + '.svg'),
        install_dir: get_option('datadir') / 'icons' / 'hicolor' / i + 'x' + i / 'apps',
        rename: meson.project_name() + '.svg'
    )
    install_data(
        join_paths('icons', i + '.svg'),
        install_dir: get_option('datadir') / 'icons' / 'hicolor' / i + 'x' + i + '@2' / 'apps',
        rename: meson.project_name() + '.svg'
    )
endforeach

install_data(
    meson.project_name() + '.gschema.xml',
    install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

# Keep a local build's WebKit user-namespace permission separate from the
# distribution package's profile, and match the actual installed executable.
apparmor_config = configuration_data()
apparmor_profile = meson.project_name()
if get_option('prefix') != '/usr'
    apparmor_profile += '.local'
endif
apparmor_config.set('PROFILE_NAME', apparmor_profile)
apparmor_config.set('BINARY_PATH', get_option('prefix') / get_option('bindir') / meson.project_name())
configure_file(
    input: meson.project_name() + '.apparmor.in',
    output: apparmor_profile,
    configuration: apparmor_config,
    install_dir: get_option('sysconfdir') / 'apparmor.d'
)

i18n.merge_file (
    input: meson.project_name() + '.desktop.in',
    output: meson.project_name() + '.desktop',
    install: true,
    install_dir: get_option('datadir') / 'applications',
    po_dir: meson.project_source_root() / 'po' / 'extra',
    type: 'desktop'
)

i18n.merge_file (
    input: 'mail.metainfo.xml.in',
    output: meson.project_name() + '.metainfo.xml',
    install: true,
    install_dir: get_option('datadir') / 'metainfo',
    po_dir: meson.project_source_root () / 'po' / 'extra'
)

build_schema = configure_file(
    input: meson.project_name() + '.gschema.xml',
    output: meson.project_name() + '.gschema.xml',
    copy: true
)
gnome.compile_schemas(depend_files: build_schema)
