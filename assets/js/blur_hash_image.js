function attachEventListener(imageElement) {
    alreadyLoaded = imageElement.complete

    // When a reload happens due to LiveView the image might already have loaded
    // and the "onload" event is not firing retroactively. If the image has loaded
    // then do an instant swap of the blur hash to the image.
    if (!alreadyLoaded) {
        imageElement.onload = function() {
            hideBlurHash(imageElement, false)
        }
    } else {
        hideBlurHash(imageElement, true)
    }
}

function hideBlurHash(imageElement, force) {
    const elementId = imageElement.id
    const blurHashCanvas = document.getElementById("blur-hash-" + elementId)
    if (force) {
        blurHashCanvas.classList.add("hidden")
    } else {
        blurHashCanvas.classList.add("transition-opacity", "ease-out", "duration-50", "opacity-0")
    }
}

module.exports = {
    mounted() {
        const element = this.el
        attachEventListener(element)
    },
    updated() {
        const element = this.el
        hideBlurHash(element, true)
    }
}