{{flutter_js}}
{{flutter_build_config}}

(function () {
  // Packaged Smart TV apps (LG webOS / Samsung Tizen) run from file:// origins.
  // Calling navigator.serviceWorker.getRegistration() on LG webOS terminates
  // the WebAppManager renderer process on startup, and local CanvasKit assets
  // must be used instead of CDN fetches.
  var isTvOrFile =
    window.location.protocol === 'file:' ||
    typeof window.tizen !== 'undefined' ||
    typeof window.webOS !== 'undefined' ||
    typeof window.PalmSystem !== 'undefined';

  var loadOptions = {
    config: isTvOrFile ? { canvasKitBaseUrl: 'canvaskit/' } : {},
    onEntrypointLoaded: async function (engineInitializer) {
      var appRunner = await engineInitializer.initializeEngine(loadOptions.config);
      await appRunner.runApp();
      var loading = document.getElementById('loading-indicator');
      if (loading && loading.parentNode) {
        loading.parentNode.removeChild(loading);
      }
    },
  };

  var swVersion = {{flutter_service_worker_version}};
  if (!isTvOrFile && swVersion) {
    loadOptions.serviceWorkerSettings = {
      serviceWorkerVersion: swVersion,
    };
  }

  _flutter.loader.load(loadOptions);
})();

