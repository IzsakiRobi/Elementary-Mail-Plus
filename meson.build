project(
    'io.elementary.mail',
    'vala', 'c',
    version: '0.2',
    meson_version: '>=0.58.0'
)

application_id = get_option('application-id')
settings_path = '/' + application_id.replace('.', '/') + '/'

gnome = import('gnome')
i18n = import('i18n')

add_project_arguments(['--vapidir', join_paths(meson.current_source_dir(), 'vapi')], language: 'vala')

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
granite_dep = dependency('granite', version: '>= 6.0.0')
gee_dep = dependency('gee-0.8')
handy_dep = dependency('libhandy-1', version: '>=1.1.90')
camel_dep = dependency('camel-1.2', version: '>= 3.58', required: false)
if camel_dep.found()
    add_project_arguments('--define=HAS_CAMEL_3_58', language: 'vala')
else
    camel_dep = dependency('camel-1.2', version: '>= 3.28')
endif
libedataserver_dep = dependency('libedataserver-1.2', version: '>= 3.28')
libedataserverui_dep = dependency('libedataserverui-1.2', version: '>=3.45.1')
webkit2_dep = dependency('webkit2gtk-4.1')
webkit2_web_extension_dep = dependency('webkit2gtk-web-extension-4.1')
libportal_dep = dependency('libportal')
libportal_gtk_dep = dependency('libportal-gtk3')
folks_dep = dependency('folks')
m_dep = meson.get_compiler('c').find_library('m')

webkit2_extension_path = join_paths(get_option('prefix'), get_option('libdir'), application_id, 'webkit2')

dependencies = [
    glib_dep,
    gobject_dep,
    granite_dep,
    gee_dep,
    handy_dep,
    camel_dep,
    libedataserver_dep,
    libedataserverui_dep,
    libportal_dep,
    libportal_gtk_dep,
    webkit2_dep,
    folks_dep,
    dependency('libsoup-3.0'),
    dependency('libsecret-1'),
    m_dep
]

asresources = gnome.compile_resources(
    'as-resources', 'data/' + meson.project_name() + '.gresource.xml',
    source_dir: 'data',
    c_name: 'as'
)

extension_dependencies = [
    glib_dep,
    gobject_dep,
    gee_dep,
    webkit2_web_extension_dep
]

add_global_arguments([
        '-DGETTEXT_PACKAGE="@0@"'.format(application_id),
        '-DHANDY_USE_UNSTABLE_API'
    ],
    language:'c'
)

gnome.post_install(glib_compile_schemas: true)

config_data = configuration_data()
config_data.set('GETTEXT_PACKAGE', application_id)
config_data.set('APPLICATION_ID', application_id)
config_data.set('IMAP_FOLDER_SETUP', get_option('imap-folder-setup') ? 'true' : 'false')
config_data.set('LOCALEDIR', join_paths(get_option('prefix'), get_option('localedir')))

config_file = configure_file(
    input: 'Config.vala.in',
    output: '@BASENAME@',
    configuration: config_data
)

subdir('src')
subdir('webkit-extension')
subdir('data')
subdir('po')
