install_subdir('icons/MailPlus', install_dir: get_option('datadir') / 'icons')

icon_sizes = ['16', '24', '32', '48', '64', '128']

foreach i : icon_sizes
    install_data(
        join_paths('icons', i + '.svg'),
        install_dir: get_option('datadir') / 'icons' / 'hicolor' / i + 'x' + i / 'apps',
        rename: application_id + '.svg'
    )
    install_data(
        join_paths('icons', i + '.svg'),
        install_dir: get_option('datadir') / 'icons' / 'hicolor' / i + 'x' + i + '@2' / 'apps',
        rename: application_id + '.svg'
    )
endforeach


# Keep a local build's WebKit user-namespace permission separate from the
# distribution package's profile, and match the actual installed executable.
apparmor_config = configuration_data()
apparmor_profile = application_id
if get_option('prefix') != '/usr'
    apparmor_profile += '.local'
endif
apparmor_config.set('PROFILE_NAME', apparmor_profile)
apparmor_config.set('BINARY_PATH', get_option('prefix') / get_option('bindir') / application_id)
configure_file(
    input: meson.project_name() + '.apparmor.in',
    output: apparmor_profile,
    configuration: apparmor_config,
    install_dir: get_option('sysconfdir') / 'apparmor.d'
)

desktop_config = configuration_data()
desktop_config.set('APPLICATION_ID', application_id)
desktop_config.set('APPLICATION_NAME', application_id == 'io.elementary.mail' ? 'Mail' : 'Mail Plus')
desktop_template = configure_file(input: 'io.elementary.mail.desktop.in', output: 'mail.desktop.in', configuration: desktop_config)

i18n.merge_file (
    input: desktop_template,
    output: application_id + '.desktop',
    install: true,
    install_dir: get_option('datadir') / 'applications',
    po_dir: meson.project_source_root() / 'po' / 'extra',
    type: 'desktop'
)

metainfo_template = configure_file(input: 'mail.metainfo.xml.in', output: 'configured.metainfo.xml.in', configuration: desktop_config)
i18n.merge_file (
    input: metainfo_template,
    output: application_id + '.metainfo.xml',
    install: true,
    install_dir: get_option('datadir') / 'metainfo',
    po_dir: meson.project_source_root () / 'po' / 'extra'
)

schema_config = configuration_data()
schema_config.set('APPLICATION_ID', application_id)
schema_config.set('SETTINGS_PATH', settings_path)
build_schema = configure_file(
    input: meson.project_name() + '.gschema.xml',
    output: application_id + '.gschema.xml',
    configuration: schema_config,
    install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
gnome.compile_schemas(depend_files: build_schema)
