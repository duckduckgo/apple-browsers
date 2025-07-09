/**
 * This script is designed to be run before the application loads, use it to set values
 * that might be needed in CSS or JS
 */

document.documentElement.dataset.platform = import.meta.injectName;
