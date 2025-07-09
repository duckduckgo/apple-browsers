function replayScript(scriptText) {
    const scriptElement = document.createElement('script');
    scriptElement.innerText = scriptText;
    document.head.appendChild(scriptElement);
}
window.replayScript = replayScript;
