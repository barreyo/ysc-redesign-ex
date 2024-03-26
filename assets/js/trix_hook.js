import Trix from '../vendor/trix'

function emitEditorUpdateEvent(source) {
    const editorElement = document.getElementById("post[raw_body]");
    source.pushEvent("editor-update", { raw_body: editorElement.value });
}

module.exports = {
    mounted() {
        window.Trix = Trix;

        document.addEventListener("trix-change", () => {
            emitEditorUpdateEvent(this);
        });

        document.addEventListener("trix-blur", () => {
            emitEditorUpdateEvent(this);
        });
    },

    updated() {
    }
}