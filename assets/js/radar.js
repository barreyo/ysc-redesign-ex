let locked = false;

export default RadarMap = {
  mounted() {
    window.Radar.initialize(
      "prj_test_pk_5bcfd56661bb7fc596d70d5f21f0e2c6049b0966",
    );

    let existingMarker = undefined;
    const elementID = this.el.getAttribute("id");
    const map = Radar.ui.map({
      container: elementID,
    });

    const setMarker = (lat, lon) => {
      if (!lat || !lon) {
        return;
      }

      if (existingMarker) {
        existingMarker.remove();
      }
      existingMarker = Radar.ui.marker().setLngLat([lon, lat]).addTo(map);
      // fit map to markers
      map.fitToMarkers({ maxZoom: 14, padding: 80 });
    };

    this.handleEvent("add-marker", ({ lat, lon, is_locked }) => {
      locked = is_locked;
      setMarker(lat, lon);
    });

    // Hack to make the zoom work on render
    setTimeout(() => {
      if (existingMarker) {
        map.fitToMarkers({ maxZoom: 14, padding: 80 });
      }
    }, 300);

    map.on("click", (e) => {
      if (locked) {
        return;
      }

      if (existingMarker) {
        existingMarker.remove();
      }

      const { lng, lat } = e.lngLat;
      // create marker from click location
      existingMarker = Radar.ui.marker().setLngLat([lng, lat]).addTo(map);

      this.pushEvent("map-new-marker", { lat: lat, long: lng });

      // fit map to markers
      map.fitToMarkers({ maxZoom: 14, padding: 80 });

      existingMarker.on("click", (e) => {
        existingMarker.remove();
        map.fitToMarkers({ maxZoom: 14, padding: 80 }); // refit after marker removed
      });
    });

    this.handleEvent("position", () => {
      map.fitToMarkers({ maxZoom: 14, padding: 80 });
    });
  },
};
