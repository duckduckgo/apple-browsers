/**
 * This code is in most parts copied from https://github.com/cavi-au/Consent-O-Matic/blob/master/Extension/Tools.js
 * which is licened under the MIT. 
 */
export default class Tools {
  static base: HTMLElement = null;

  static setBase(base: HTMLElement) {
    Tools.base = base;
  }

  static findElement(options: any, parent: any = null, multiple = false): HTMLElement[] | HTMLElement {
    let possibleTargets = null;

    if (parent != null) {
      possibleTargets = Array.from(parent.querySelectorAll(options.selector));
    } else {
      if (Tools.base != null) {
        possibleTargets = Array.from(
          Tools.base.querySelectorAll(options.selector)
        );
      } else {
        possibleTargets = Array.from(
          document.querySelectorAll(options.selector)
        );
      }
    }

    if (options.textFilter != null) {
      possibleTargets = possibleTargets.filter(possibleTarget => {
        const textContent = possibleTarget.textContent.toLowerCase();

        if (Array.isArray(options.textFilter)) {
          let foundText = false;

          for (const text of options.textFilter) {
            if (textContent.indexOf(text.toLowerCase()) !== -1) {
              foundText = true;
              break;
            }
          }

          return foundText;
        } else if (options.textFilter != null) {
          return textContent.indexOf(options.textFilter.toLowerCase()) !== -1;
        }
        return false;
      });
    }

    if (options.styleFilters != null) {
      possibleTargets = possibleTargets.filter(possibleTarget => {
        const styles = window.getComputedStyle(possibleTarget);

        let keep = true;

        for (const styleFilter of options.styleFilters) {
          const option = styles[styleFilter.option];

          if (styleFilter.negated) {
            keep = keep && option !== styleFilter.value;
          } else {
            keep = keep && option === styleFilter.value;
          }
        }

        return keep;
      });
    }

    if (options.displayFilter != null) {
      possibleTargets = possibleTargets.filter(possibleTarget => {
        if (options.displayFilter) {
          // We should be displayed
          return possibleTarget.offsetHeight !== 0;
        } else {
          // We should not be displayed
          return possibleTarget.offsetHeight === 0;
        }
      });
    }

    if (options.iframeFilter != null) {
      possibleTargets = possibleTargets.filter((/* possibleTarget */) => {
        if (options.iframeFilter) {
          // We should be inside an iframe
          return window.location !== window.parent.location;
        } else {
          // We should not be inside an iframe
          return window.location === window.parent.location;
        }
      });
    }

    if (options.childFilter != null) {
      possibleTargets = possibleTargets.filter(possibleTarget => {
        const oldBase = Tools.base;
        Tools.setBase(possibleTarget);
        const childResults = Tools.find(options.childFilter);
        Tools.setBase(oldBase);
        return childResults.target != null;
      });
    }

    if (multiple) {
      return possibleTargets;
    } else {
      if (possibleTargets.length > 1) {
        console.warn(
          "Multiple possible targets: ",
          possibleTargets,
          options,
          parent
        );
      }

      return possibleTargets[0];
    }
  }

  static find(options: any, multiple = false) {
    const results: any[] = [];
    if (options.parent != null) {
      const parent = Tools.findElement(options.parent, null, multiple);
      if (parent != null) {
        if (parent instanceof Array) {
          parent.forEach(p => {
            const targets = Tools.findElement(options.target, p, multiple);
            if (targets instanceof Array) {
              targets.forEach(target => {
                results.push({
                  parent: p,
                  target
                });
              });
            } else {
              results.push({
                parent: p,
                target: targets
              });
            }
          });

          return results;
        } else {
          const targets = Tools.findElement(options.target, parent, multiple);
          if (targets instanceof Array) {
            targets.forEach(target => {
              results.push({
                parent,
                target
              });
            });
          } else {
            results.push({
              parent,
              target: targets
            });
          }
        }
      }
    } else {
      const targets = Tools.findElement(options.target, null, multiple);
      if (targets instanceof Array) {
        targets.forEach(target => {
          results.push({
            parent: null,
            target
          });
        });
      } else {
        results.push({
          parent: null,
          target: targets
        });
      }
    }

    if (results.length === 0) {
      results.push({
        parent: null,
        target: null
      });
    }

    if (multiple) {
      return results;
    } else {
      if (results.length !== 1) {
        console.warn(
          "Multiple results found, even though multiple false",
          results
        );
      }

      return results[0];
    }
  }
}
