import css from './assets/styles.css';
import { SideEffects, VideoParams } from './util.js';
import dax from './assets/dax.svg';
import { i18n } from './text.js';
import { createPolicy, html, trustedUnsafe } from '../../dom-utils.js';

export class IconOverlay {
    sideEffects = new SideEffects();
    policy = createPolicy();

    /** @type {HTMLElement | null} */
    element = null;
    /**
     * Special class used for the overlay hover. For hovering, we use a
     * single element and move it around to the hovered video element.
     */
    HOVER_CLASS = 'ddg-overlay-hover';
    OVERLAY_CLASS = 'ddg-overlay';

    CSS_OVERLAY_MARGIN_TOP = 5;
    CSS_OVERLAY_HEIGHT = 32;

    /** @type {HTMLElement | null} */
    currentVideoElement = null;
    hoverOverlayVisible = false;

    /**
     * Creates an Icon Overlay.
     * @param {string} size - currently kind-of unused
     * @param {string} href - what, if any, href to set the link to by default.
     * @param {string} [extraClass] - whether to add any extra classes, such as hover
     * @returns {HTMLElement}
     */
    create(size, href, extraClass) {
        const overlayElement = document.createElement('div');

        overlayElement.setAttribute('class', 'ddg-overlay' + (extraClass ? ' ' + extraClass : ''));
        overlayElement.setAttribute('data-size', size);
        const svgIcon = trustedUnsafe(dax);
        const safeString = html` <a class="ddg-play-privately" href="#">
            <div class="ddg-dax">${svgIcon}</div>
            <div class="ddg-play-text-container">
                <div class="ddg-play-text">${i18n.t('playText')}</div>
            </div>
        </a>`.toString();

        overlayElement.innerHTML = this.policy.createHTML(safeString);

        overlayElement.querySelector('a.ddg-play-privately')?.setAttribute('href', href);
        return overlayElement;
    }

    /**
     * Util to return the hover overlay
     * @returns {HTMLElement | null}
     */
    getHoverOverlay() {
        return document.querySelector('.' + this.HOVER_CLASS);
    }

    /**
     * Moves the hover overlay to a specified videoElement
     * @param {HTMLElement} videoElement - which element to move it to
     */
    moveHoverOverlayToVideoElement(videoElement) {
        const overlay = this.getHoverOverlay();

        if (overlay === null || this.videoScrolledOutOfViewInPlaylist(videoElement)) {
            return;
        }

        const videoElementOffset = this.getElementOffset(videoElement);

        overlay.setAttribute(
            'style',
            '' + 'top: ' + videoElementOffset.top + 'px;' + 'left: ' + videoElementOffset.left + 'px;' + 'display:block;',
        );

        overlay.setAttribute('data-size', 'fixed ' + this.getThumbnailSize(videoElement));

        const href = videoElement.getAttribute('href');

        if (href) {
            const privateUrl = VideoParams.fromPathname(href)?.toPrivatePlayerUrl();
            if (overlay && privateUrl) {
                overlay.querySelector('a')?.setAttribute('href', privateUrl);
            }
        }

        this.hoverOverlayVisible = true;
        this.currentVideoElement = videoElement;
    }

    /**
     * Returns true if the videoElement is scrolled out of view in a playlist. (In these cases
     * we don't want to show the overlay.)
     * @param {HTMLElement} videoElement
     * @returns {boolean}
     */
    videoScrolledOutOfViewInPlaylist(videoElement) {
        const inPlaylist = videoElement.closest('#items.playlist-items');

        if (inPlaylist) {
            const video = videoElement.getBoundingClientRect();
            const playlist = inPlaylist.getBoundingClientRect();

            const videoOutsideTop = video.top + this.CSS_OVERLAY_MARGIN_TOP < playlist.top;
            const videoOutsideBottom = video.top + this.CSS_OVERLAY_HEIGHT + this.CSS_OVERLAY_MARGIN_TOP > playlist.bottom;

            if (videoOutsideTop || videoOutsideBottom) {
                return true;
            }
        }

        return false;
    }

    /**
     * Return the offset of an HTML Element
     * @param {HTMLElement} el
     * @returns {Object}
     */
    getElementOffset(el) {
        const box = el.getBoundingClientRect();
        const docElem = document.documentElement;
        return {
            top: box.top + window.pageYOffset - docElem.clientTop,
            left: box.left + window.pageXOffset - docElem.clientLeft,
        };
    }

    /**
     * Hides the hover overlay element, but only if mouse pointer is outside of the hover overlay element
     */
    hideHoverOverlay(event, force) {
        const overlay = this.getHoverOverlay();

        const toElement = event.toElement;

        if (overlay) {
            // Prevent hiding overlay if mouseleave is triggered by user is actually hovering it and that
            // triggered the mouseleave event
            if (toElement === overlay || overlay.contains(toElement) || force) {
                return;
            }

            this.hideOverlay(overlay);
            this.hoverOverlayVisible = false;
        }
    }

    /**
     * Util for hiding an overlay
     * @param {HTMLElement} overlay
     */
    hideOverlay(overlay) {
        overlay.setAttribute('style', 'display:none;');
    }

    /**
     * Appends the Hover Overlay to the page. This is the one that is shown on hover of any video thumbnail.
     * More performant / clean than adding an overlay to each and every video thumbnail. Also it prevents triggering
     * the video hover preview on the homepage if the user hovers the overlay, because user is no longer hovering
     * inside a video thumbnail when hovering the overlay. Nice.
     * @param {(href: string) => void} onClick
     */
    appendHoverOverlay(onClick) {
        this.sideEffects.add('Adding the re-usable overlay to the page ', () => {
            // add the CSS to the head
            const cleanUpCSS = this.loadCSS();

            // create and append the element
            const element = this.create('fixed', '', this.HOVER_CLASS);
            document.body.appendChild(element);

            this.addClickHandler(element, onClick);

            return () => {
                element.remove();
                cleanUpCSS();
            };
        });
    }

    loadCSS() {
        // add the CSS to the head
        const id = '__ddg__icon';
        const style = document.head.querySelector(`#${id}`);
        if (!style) {
            const style = document.createElement('style');
            style.id = id;
            style.textContent = css;
            document.head.appendChild(style);
        }
        return () => {
            const style = document.head.querySelector(`#${id}`);
            if (style) {
                document.head.removeChild(style);
            }
        };
    }

    /**
     * @param {HTMLElement} container
     * @param {string} href
     * @param {(href: string) => void} onClick
     */
    appendSmallVideoOverlay(container, href, onClick) {
        this.sideEffects.add('Adding a small overlay for the video player', () => {
            // add the CSS to the head
            const cleanUpCSS = this.loadCSS();

            const element = this.create('video-player', href, 'hidden');

            this.addClickHandler(element, onClick);

            container.appendChild(element);
            element.classList.remove('hidden');

            return () => {
                element?.remove();
                cleanUpCSS();
            };
        });
    }

    getThumbnailSize(videoElement) {
        const imagesByArea = {};

        Array.from(videoElement.querySelectorAll('img')).forEach((image) => {
            imagesByArea[image.offsetWidth * image.offsetHeight] = image;
        });

        const largestImage = Math.max.apply(this, Object.keys(imagesByArea).map(Number));

        const getSizeType = (width, height) => {
            if (width < 123 + 10) {
                // match CSS: width of expanded overlay + twice the left margin.
                return 'small';
            } else if (width < 300 && height < 175) {
                return 'medium';
            } else {
                return 'large';
            }
        };

        return getSizeType(imagesByArea[largestImage].offsetWidth, imagesByArea[largestImage].offsetHeight);
    }

    /**
     * Handle when dax is clicked - prevent propagation
     * so no further listeners see this
     *
     * @param {HTMLElement} element - the wrapping div
     * @param {(href: string) => void} callback - the function to execute following a click
     */
    addClickHandler(element, callback) {
        element.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopImmediatePropagation();
            const link = /** @type {HTMLElement} */ (event.target).closest('a');
            const href = link?.getAttribute('href');
            if (href) {
                callback(href);
            }
        });
    }

    destroy() {
        this.sideEffects.destroy();
    }
}
