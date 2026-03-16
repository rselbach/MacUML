window.currentTheme = 'auto';
window.renderSequence = 0;

function collectUnexpectedBodyNodes() {
    const diagram = document.getElementById('diagram');
    if (!diagram) return [];
    return Array.from(document.body.childNodes).filter((node) => {
        if (node === diagram) return false;
        if (node instanceof Element &&
            node.getAttribute('data-macuml-role') === 'temp-render') {
            return false;
        }
        if (node.nodeType === Node.TEXT_NODE) {
            return (node.textContent || '').trim().length > 0;
        }
        return true;
    });
}

function cleanupUnexpectedBodyNodes(reason) {
    const unexpectedNodes = collectUnexpectedBodyNodes();
    if (unexpectedNodes.length === 0) return;

    console.warn('[MermaidPreview] Removing unexpected body nodes', {
        reason,
        count: unexpectedNodes.length
    });
    unexpectedNodes.forEach((node) => node.remove());
}

window.collectPreviewDiagnostics = function() {
    const unexpectedNodes = collectUnexpectedBodyNodes();
    return {
        extraNodeCount: unexpectedNodes.length
    };
};

function getEffectiveTheme() {
    if (window.currentTheme === 'auto') {
        return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default';
    }
    return window.currentTheme;
}

function initMermaid() {
    mermaid.initialize({
        startOnLoad: false,
        theme: getEffectiveTheme(),
        securityLevel: 'strict',
        fontFamily: 'system-ui, -apple-system, sans-serif'
    });
}

function updateBackground() {
    const theme = getEffectiveTheme();
    const container = document.getElementById('diagram');
    const useDark = theme === 'dark' ||
        (window.currentTheme === 'auto' && window.matchMedia('(prefers-color-scheme: dark)').matches);
    container.classList.remove('dark-bg', 'light-bg');
    container.classList.add(useDark ? 'dark-bg' : 'light-bg');
}

document.addEventListener('DOMContentLoaded', () => {
    initMermaid();
    updateBackground();
    cleanupUnexpectedBodyNodes('DOMContentLoaded');

    // MutationObserver runs continuously to clean up unexpected DOM nodes that Mermaid may inject.
    // This is intentional simplicity vs. conditional activation.
    const observer = new MutationObserver((mutations) => {
        let hasUnexpectedMutation = false;
        const diagram = document.getElementById('diagram');

        for (const mutation of mutations) {
            for (const addedNode of mutation.addedNodes) {
                if (!diagram) continue;
                if (addedNode === diagram) continue;
                if (diagram.contains(addedNode)) continue;
                if (addedNode instanceof Element &&
                    addedNode.getAttribute('data-macuml-role') === 'temp-render') {
                    continue;
                }
                if (addedNode.nodeType === Node.TEXT_NODE &&
                    (addedNode.textContent || '').trim().length === 0) {
                    continue;
                }
                hasUnexpectedMutation = true;
                break;
            }
            if (hasUnexpectedMutation) break;
        }

        if (hasUnexpectedMutation) {
            cleanupUnexpectedBodyNodes('mutation-observer');
        }
    });
    observer.observe(document.body, { childList: true });

    window.webkit.messageHandlers.ready.postMessage(true);
});

window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if (window.currentTheme === 'auto') {
        initMermaid();
        updateBackground();
        if (window.lastSource) {
            window.renderDiagram(window.lastSource);
        }
    }
});

window.setTheme = async function(theme) {
    window.currentTheme = theme;
    initMermaid();
    updateBackground();
    if (window.lastSource) {
        await window.renderDiagram(window.lastSource);
    }
};

window.zoomLevel = 1.0;
window.panX = 0;
window.panY = 0;
const ZOOM_STEP = 0.1;
const ZOOM_MIN = 0.25;
const ZOOM_MAX = 5.0;

function hasRenderedSVG() {
    return document.querySelector('#diagram svg') !== null;
}

function updateInteractionState() {
    const container = document.getElementById('diagram');
    if (!container) return;
    container.classList.toggle('has-diagram', hasRenderedSVG());
}

function applyPan() {
    const container = document.getElementById('diagram');
    const panInner = container.querySelector('.pan-inner');
    if (!panInner) return;
    panInner.style.transform = 'translate(' + window.panX + 'px, ' + window.panY + 'px)';
}

function panBounds(zoomLevel) {
    const container = document.getElementById('diagram');
    const width = container ? container.clientWidth : 0;
    const height = container ? container.clientHeight : 0;
    const zoom = Number.isFinite(zoomLevel) ? zoomLevel : window.zoomLevel;
    const maxX = Math.max(0, ((width * zoom) - width) / 2);
    const maxY = Math.max(0, ((height * zoom) - height) / 2);
    return { maxX, maxY };
}

function clampPan(x, y, zoomLevel) {
    const bounds = panBounds(zoomLevel);
    return {
        x: Math.max(-bounds.maxX, Math.min(bounds.maxX, x)),
        y: Math.max(-bounds.maxY, Math.min(bounds.maxY, y))
    };
}

function applyZoom() {
    const container = document.getElementById('diagram');
    const inner = container.querySelector('.zoom-inner');
    if (!inner) return;
    inner.style.transform = 'scale(' + window.zoomLevel + ')';
    inner.style.transformOrigin = 'center center';
    if (window.webkit && window.webkit.messageHandlers.zoomChanged) {
        window.webkit.messageHandlers.zoomChanged.postMessage(window.zoomLevel);
    }
}

window.setPan = function(x, y) {
    const clamped = clampPan(x, y, window.zoomLevel);
    window.panX = clamped.x;
    window.panY = clamped.y;
    applyPan();
    return { x: window.panX, y: window.panY };
};

window.setZoom = function(level, anchorClientX, anchorClientY) {
    const container = document.getElementById('diagram');
    const oldZoom = window.zoomLevel;
    const newZoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, level));
    let nextPanX = window.panX;
    let nextPanY = window.panY;

    if (Number.isFinite(anchorClientX) && Number.isFinite(anchorClientY) && oldZoom > 0) {
        const rect = container.getBoundingClientRect();
        const localX = anchorClientX - rect.left;
        const localY = anchorClientY - rect.top;
        const centerX = container.clientWidth / 2;
        const centerY = container.clientHeight / 2;
        const ratio = newZoom / oldZoom;
        nextPanX = (ratio * window.panX) + ((1 - ratio) * (localX - centerX));
        nextPanY = (ratio * window.panY) + ((1 - ratio) * (localY - centerY));
    }

    const clamped = clampPan(nextPanX, nextPanY, newZoom);
    window.panX = clamped.x;
    window.panY = clamped.y;
    window.zoomLevel = newZoom;
    applyPan();
    applyZoom();
    return window.zoomLevel;
};

window.zoomIn = function() {
    return window.setZoom(Math.round((window.zoomLevel + ZOOM_STEP) * 100) / 100);
};

window.zoomOut = function() {
    return window.setZoom(Math.round((window.zoomLevel - ZOOM_STEP) * 100) / 100);
};

window.resetZoom = function() {
    return window.setZoom(1.0);
};

window.getZoom = function() {
    return window.zoomLevel;
};

window.rescaleSVG = function() {
    const container = document.getElementById('diagram');
    const inner = container.querySelector('.zoom-inner');
    const svgEl = inner ? inner.querySelector('svg') : container.querySelector('svg');
    if (!svgEl) return;

    svgEl.removeAttribute('style');
    svgEl.style.display = 'block';
    svgEl.style.maxWidth = 'none';
    svgEl.style.maxHeight = 'none';
    svgEl.style.width = '100%';
    svgEl.style.height = '100%';
    svgEl.setAttribute('preserveAspectRatio', 'xMidYMid meet');
};

// ResizeObserver runs continuously for responsive SVG scaling. Intentional simplicity.
new ResizeObserver(() => {
    window.rescaleSVG();
    window.setPan(window.panX, window.panY);
}).observe(document.documentElement);

function initInteractions() {
    const container = document.getElementById('diagram');
    if (!container || container.dataset.interactionsBound === '1') return;
    container.dataset.interactionsBound = '1';

    let isPanning = false;
    let activePointerId = null;
    let lastX = 0;
    let lastY = 0;
    let gestureStartZoom = 1.0;

    container.addEventListener('pointerdown', (event) => {
        if (event.button !== 0 || !hasRenderedSVG()) return;
        isPanning = true;
        activePointerId = event.pointerId;
        lastX = event.clientX;
        lastY = event.clientY;
        container.classList.add('is-panning');
        container.setPointerCapture(event.pointerId);
        event.preventDefault();
    });

    container.addEventListener('pointermove', (event) => {
        if (!isPanning || event.pointerId !== activePointerId) return;
        const dx = event.clientX - lastX;
        const dy = event.clientY - lastY;
        lastX = event.clientX;
        lastY = event.clientY;
        window.setPan(window.panX + dx, window.panY + dy);
        event.preventDefault();
    });

    function stopPanning(event) {
        if (!isPanning) return;
        if (activePointerId !== null && event.pointerId !== activePointerId) return;
        isPanning = false;
        activePointerId = null;
        container.classList.remove('is-panning');
    }

    container.addEventListener('pointerup', stopPanning);
    container.addEventListener('pointercancel', stopPanning);
    container.addEventListener('lostpointercapture', stopPanning);

    container.addEventListener('wheel', (event) => {
        if (!hasRenderedSVG()) return;
        event.preventDefault();
        const delta = event.deltaY === 0 ? event.deltaX : event.deltaY;
        if (delta === 0) return;
        const scaleFactor = Math.exp(-delta * 0.002);
        const targetZoom = window.zoomLevel * scaleFactor;
        window.setZoom(targetZoom, event.clientX, event.clientY);
    }, { passive: false });

    document.addEventListener('gesturestart', (event) => {
        if (!hasRenderedSVG()) return;
        gestureStartZoom = window.zoomLevel;
        event.preventDefault();
    }, { passive: false });

    document.addEventListener('gesturechange', (event) => {
        if (!hasRenderedSVG()) return;
        event.preventDefault();
        window.setZoom(gestureStartZoom * event.scale, event.clientX, event.clientY);
    }, { passive: false });
}

window.renderDiagram = async function(source) {
    window.lastSource = source;
    const renderSequence = ++window.renderSequence;
    const container = document.getElementById('diagram');
    const tempContainer = document.createElement('div');
    tempContainer.style.position = 'fixed';
    tempContainer.style.left = '-10000px';
    tempContainer.style.top = '0';
    tempContainer.style.visibility = 'hidden';
    tempContainer.style.pointerEvents = 'none';
    tempContainer.setAttribute('data-macuml-role', 'temp-render');
    tempContainer.setAttribute('aria-hidden', 'true');
    document.body.appendChild(tempContainer);

    try {
        const id = 'mermaid-' + renderSequence + '-' + Date.now();
        const { svg } = await mermaid.render(id, source, tempContainer);
        if (renderSequence !== window.renderSequence) {
            return { success: true, stale: true };
        }

        const hasError = svg.includes('Syntax error') || svg.includes('Parse error');

        if (svg && !hasError) {
            container.innerHTML = '<div class="pan-inner"><div class="zoom-inner">' + svg + '</div></div>';
            updateInteractionState();
            applyPan();
            applyZoom();
            window.rescaleSVG();
            cleanupUnexpectedBodyNodes('render-success');
            return { success: true };
        } else {
            const errorText = tempContainer.textContent || 'Syntax error in diagram';
            cleanupUnexpectedBodyNodes('render-error-content');
            return { success: false, error: errorText.trim().substring(0, 200) };
        }
    } catch (e) {
        let line = null;
        const msg = e.message || String(e);

        const patterns = [
            /line\s*(\d+)/i,
            /on line (\d+)/i,
            /at line (\d+)/i,
            /:(\d+):/,
            /\((\d+):(\d+)\)/
        ];

        for (const pattern of patterns) {
            const match = msg.match(pattern);
            if (match) {
                line = parseInt(match[1], 10);
                break;
            }
        }

        return { success: false, error: msg, line: line };
    } finally {
        tempContainer.remove();
        cleanupUnexpectedBodyNodes('render-finally');
    }
};

document.addEventListener('DOMContentLoaded', () => {
    initInteractions();
    updateInteractionState();
});
