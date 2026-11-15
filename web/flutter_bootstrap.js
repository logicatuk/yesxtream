{{flutter_js}}
{{flutter_build_config}}

(function () {
  // Smart TV / packaged apps (LG webOS, Samsung Tizen) run from a file:// origin.
  // Calling navigator.serviceWorker.getRegistration() on LG webOS terminates
  // the WebAppManager renderer process on startup, and local CanvasKit assets
  // must be used instead of CDN fetches.
  var isTvOrFile =
    window.location.protocol === 'file:' ||
    typeof window.tizen !== 'undefined' ||
    typeof window.webOS !== 'undefined' ||
    typeof window.PalmSystem !== 'undefined';

  // One CanvasKit surface keeps webOS / Tizen GPUs from juggling overlays.
  // Those chips stall when Flutter promotes every clip and opacity to its
  // own surface.
  var config = isTvOrFile
    ? {
        canvasKitBaseUrl: 'canvaskit/',
        canvasKitVariant: 'chromium',
        canvasKitMaximumSurfaces: 1,
      }
    : {};

  var loadOptions = {
    config: config,
    onEntrypointLoaded: async function (engineInitializer) {
      var appRunner = await engineInitializer.initializeEngine(config);
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
