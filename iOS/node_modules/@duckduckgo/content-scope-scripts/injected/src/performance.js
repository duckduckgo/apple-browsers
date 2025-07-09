/**
 * Performance monitor, holds reference to PerformanceMark instances.
 */
export class PerformanceMonitor {
    constructor() {
        this.marks = [];
    }

    /**
     * Create performance marker
     * @param {string} name
     * @returns {PerformanceMark}
     */
    mark(name) {
        const mark = new PerformanceMark(name);
        this.marks.push(mark);
        return mark;
    }

    /**
     * Measure all performance markers
     */
    measureAll() {
        this.marks.forEach((mark) => {
            mark.measure();
        });
    }
}

/**
 * Tiny wrapper around performance.mark and performance.measure
 */
// eslint-disable-next-line no-redeclare
export class PerformanceMark {
    /**
     * @param {string} name
     */
    constructor(name) {
        this.name = name;
        performance.mark(this.name + 'Start');
    }

    end() {
        performance.mark(this.name + 'End');
    }

    measure() {
        performance.measure(this.name, this.name + 'Start', this.name + 'End');
    }
}
