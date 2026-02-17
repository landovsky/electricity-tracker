if defined?(HotwireLivereload)
  Rails.application.configure do
    # Force full page reload instead of Turbo.visit() to avoid race condition
    # where the livereload JS references window.Turbo before the importmap
    # module has finished loading.
    config.hotwire_livereload.force_reload_paths = %w[
      app/views
      app/assets
      app/components
      app/helpers
      app/javascript
      config/locales
    ]
  end
end
