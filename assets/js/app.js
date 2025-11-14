// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import LivePhone from "./live_phone";
import StickyNavbar from "./sticky_navbar";
import Uploaders from "./uploaders";
import BlurHashCanvas from "./blur_hash_canvas";
import BlurHashImage from "./blur_hash_image";
import GrowingInput from "./growing_input_field";
import TrixHook from "./trix_hook";
import DaterangeHover from "./daterange-hover";
import CalendarHover from "./calendar_hover";
import Sortable from "./sortable";
import RadarMap from "./radar";
import MoneyInput from "./money_input";
import Turnstile from "./phoenix_turnstile";
import StripeInput from "./stripe_payment";
import StripeElements from "./stripe_elements";
import CheckoutTimer from "./checkout_timer";
import PanelResizer from "./panel_resizer";
import EmailPreview from "./email_preview";
import AdminSearch from "./admin_search";

let Hooks = {
    StickyNavbar,
    BlurHashCanvas,
    BlurHashImage,
    GrowingInput,
    TrixHook,
    DaterangeHover,
    CalendarHover,
    Sortable,
    RadarMap,
    MoneyInput,
    Turnstile,
    StripeInput,
    StripeElements,
    CheckoutTimer,
    PanelResizer,
    EmailPreview,
    AdminSearch,
};
Hooks.LivePhone = LivePhone;

let csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
    params: {
        _csrf_token: csrfToken,
        locale: Intl.NumberFormat().resolvedOptions().locale,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        timezone_offset: -(new Date().getTimezoneOffset() / 60),
    },
    hooks: Hooks,
    uploaders: Uploaders,
});

window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs();
    window.liveReloader = reloader;
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// Handle map toggle text updates
window.addEventListener("phx:toggle-map-text", () => {
    const buttonText = document.getElementById("map-button-text");
    const mapElement = document.getElementById("event-map");

    if (buttonText && mapElement) {
        if (!mapElement.classList.contains("hidden")) {
            buttonText.textContent = "Show Map";
        } else {
            buttonText.textContent = "Hide Map";
        }
    }
});

// Handle CSV download
window.addEventListener("phx:download-csv", (e) => {
    const { content, filename } = e.detail;

    // Decode base64 content
    const binaryString = atob(content);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }

    // Create blob and download
    const blob = new Blob([bytes], { type: "text/csv;charset=utf-8;" });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.URL.revokeObjectURL(url);
});

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;