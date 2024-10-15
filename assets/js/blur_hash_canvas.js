import { decode } from "../vendor/blur_hash"

function applyBlurHash(canvasElement) {
    const hash = canvasElement.getAttribute("src")
    const pixels = decode(hash, 300, 300)
    const ctx = canvasElement.getContext("2d")
    const imageData = ctx.createImageData(300, 300)
    imageData.data.set(pixels)
    ctx.putImageData(imageData, 0, 0)
}

module.exports = {
    mounted() {
        const element = this.el
        applyBlurHash(element)
    },
    updated() {
        const element = this.el
        applyBlurHash(element)
        element.classList.add("hidden")
    }
}