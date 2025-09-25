#!/usr/bin/env node

const { Builder, By, until } = require('selenium-webdriver');
const safari = require('selenium-webdriver/safari');
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
if (args.length < 1 || args.includes('--help') || args.includes('-h')) {
    console.log('Usage: node safari-performance-test.js <URL> [iterations] [output-folder]');
    console.log('');
    console.log('Arguments:');
    console.log('  URL           The URL to test');
    console.log('  iterations    Number of test iterations (default: 1)');
    console.log('  output-folder Output folder for results (default: current directory)');
    console.log('');
    console.log('Examples:');
    console.log('  node safari-performance-test.js https://example.com');
    console.log('  node safari-performance-test.js https://example.com 5');
    console.log('  node safari-performance-test.js https://example.com 5 ./results');
    process.exit(0);
}

const targetUrl = args[0];
const iterations = parseInt(args[1]) || 1;
const outputFolder = args[2] || '.';

const performanceMetricsPath = path.join(__dirname, '../Resources/performanceMetrics.js');

async function loadPerformanceMetricsScript() {
    try {
        // Load the script content - now it's a function definition
        const scriptContent = fs.readFileSync(performanceMetricsPath, 'utf8');
        return scriptContent;
    } catch (error) {
        console.error(`Error loading performance metrics script: ${error.message}`);
        console.error(`Please ensure the file exists at: ${performanceMetricsPath}`);
        process.exit(1);
    }
}

async function runSingleTest(driver, url, metricsScript) {
    try {
        await driver.get(url);

        // Wait for body element to be present
        await driver.wait(until.elementLocated(By.css('body')), 30000);

        // Wait for page to be completely loaded using multiple checks
        await driver.wait(async () => {
            const state = await driver.executeScript(`
                return {
                    readyState: document.readyState,
                    hasNav: performance.getEntriesByType('navigation').length > 0,
                    loadEventEnd: performance.getEntriesByType('navigation')[0]?.loadEventEnd || 0
                };
            `);
            // Page is ready when document is complete AND navigation timing is populated
            return state.readyState === 'complete' && state.hasNav && state.loadEventEnd > 0;
        }, 30000);

        // Short wait to ensure everything is stable (matching Swift's 500ms)
        await driver.sleep(500);

        // Scroll to trigger any lazy-loaded content and LCP
        await driver.executeScript('window.scrollTo(0, 300);');
        await driver.sleep(500);

        // Scroll more to potentially trigger more layout shifts
        await driver.executeScript('window.scrollTo(0, 600);');
        await driver.sleep(500);

        // Now execute the metrics script - at this point everything should be ready
        // Load the function definition and then call it, matching the Swift implementation
        const fullScript = metricsScript + '; return collectPerformanceMetrics();';
        const metrics = await driver.executeScript(fullScript);

        // Check if metrics is null - it shouldn't be at this point
        if (!metrics) {
            // If it's null, the script checked document.readyState and it wasn't complete
            // Even though we waited. Let's try once more with a short delay
            await driver.sleep(500);

            // Try again
            const retryMetrics = await driver.executeScript(fullScript);
            if (retryMetrics) {
                return {
                    success: true,
                    url: url,
                    timestamp: new Date().toISOString(),
                    metrics: retryMetrics
                };
            }

            throw new Error('Failed to collect metrics - script returned null after retry');
        }

        if (metrics.error) {
            throw new Error(`Metrics collection error: ${metrics.error}`);
        }

        return {
            success: true,
            url: url,
            timestamp: new Date().toISOString(),
            metrics: metrics
        };
    } catch (error) {
        return {
            success: false,
            url: url,
            timestamp: new Date().toISOString(),
            error: error.message,
            metrics: null
        };
    }
}

async function runTests() {
    const metricsScript = await loadPerformanceMetricsScript();

    console.log(`Starting Safari performance test`);
    console.log(`URL: ${targetUrl}`);
    console.log(`Iterations: ${iterations}`);
    console.log('');

    const results = {
        testConfiguration: {
            url: targetUrl,
            iterations: iterations,
            browser: 'Safari',
            startTime: new Date().toISOString()
        },
        iterations: []
    };

    let driver;

    try {
        const options = new safari.Options();
        driver = await new Builder()
            .forBrowser('safari')
            .setSafariOptions(options)
            .build();

        for (let i = 0; i < iterations; i++) {
            console.log(`Running iteration ${i + 1} of ${iterations}...`);

            const iterationResult = await runSingleTest(driver, targetUrl, metricsScript);
            results.iterations.push({
                iteration: i + 1,
                ...iterationResult
            });

            if (iterationResult.success) {
                console.log(`  ✓ Completed successfully`);
            } else {
                console.log(`  ✗ Failed: ${iterationResult.error}`);
            }

            if (i < iterations - 1) {
                // Short delay between iterations
                await driver.sleep(500);
            }
        }

    } catch (error) {
        console.error(`Fatal error: ${error.message}`);
        results.error = error.message;
    } finally {
        if (driver) {
            await driver.quit();
        }
    }

    results.testConfiguration.endTime = new Date().toISOString();

    // Ensure output folder exists
    if (!fs.existsSync(outputFolder)) {
        fs.mkdirSync(outputFolder, { recursive: true });
    }

    const outputJson = JSON.stringify(results, null, 2);
    console.log('\n=== Test Results (JSON) ===\n');
    console.log(outputJson);

    const outputFile = path.join(outputFolder, `safari-performance-results-${Date.now()}.json`);
    fs.writeFileSync(outputFile, outputJson);
    console.log(`\n✓ Results saved to: ${outputFile}`);
}

runTests().catch(error => {
    console.error('Unhandled error:', error);
    process.exit(1);
});