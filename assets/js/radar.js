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

    this.handleEvent("add_marker", ({ reference, lat, lon }) => {
      console.log("YOOOOOO DDOSABBROO");
      // lets not add duplicates for the same marker!

      if (existingMarker) {
        existingMarker.remove();
      }
      existingMarker = Radar.ui
        .marker()
        .setLngLat([-73.99055, 40.735225])
        .addTo(map);
      // fit map to markers
      map.fitToMarkers({ maxZoom: 14, padding: 80 });
    });

    map.on("click", (e) => {
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
      console.log("Position!");
      map.fitToMarkers({ maxZoom: 14, padding: 80 });
    });
  },
};
