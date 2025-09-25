# Safari Performance Test - Simplified Version

A streamlined Safari performance testing tool that measures web page performance metrics using Selenium WebDriver.

## Features

- Command-line interface for single URL testing
- Configurable number of iterations
- Injects custom performance metrics script from the Resources directory
- Outputs results in JSON format
- Calculates statistical summaries (mean, median, min, max)

## Prerequisites

1. **Node.js** (v14 or higher)
2. **Safari browser** with Remote Automation enabled:
   - Open Safari
   - Go to Safari → Preferences → Advanced
   - Check "Show Develop menu in menu bar"
   - Go to Develop → Allow Remote Automation

## Installation

Navigate to this directory and install dependencies:
```bash
cd macOS/LocalPackages/PerformanceTest/Sources/PerformanceTest/ThirdPartyBrowser
npm install
```

## Usage

```bash
node safari-performance-test.js <URL> [iterations]
```

### Arguments

- `URL` (required): The URL to test
- `iterations` (optional): Number of test iterations (default: 1)

### Examples

Test a single URL once:
```bash
node safari-performance-test.js https://example.com
```

Test a URL with 5 iterations:
```bash
node safari-performance-test.js https://example.com 5
```

## Output

The tool outputs results in two ways:

1. **Console output**: Real-time progress and final JSON results
2. **JSON file**: Saved as `safari-performance-results-{timestamp}.json` in the current directory

### Output Structure

```json
{
  "testConfiguration": {
    "url": "https://example.com",
    "iterations": 5,
    "browser": "Safari",
    "startTime": "2024-01-01T00:00:00.000Z",
    "endTime": "2024-01-01T00:01:00.000Z"
  },
  "iterations": [
    {
      "iteration": 1,
      "success": true,
      "url": "https://example.com",
      "timestamp": "2024-01-01T00:00:10.000Z",
      "metrics": {
        "loadComplete": 1234,
        "domComplete": 1000,
        "fcp": 500,
        "ttfb": 200,
        ...
      }
    }
  ],
  "summary": {
    "successfulIterations": 5,
    "failedIterations": 0,
    "metrics": {
      "loadComplete": {
        "mean": 1234.5,
        "median": 1230,
        "min": 1200,
        "max": 1300,
        "count": 5
      },
      ...
    }
  }
}
```

## Metrics Collected

The tool uses the performance metrics script from `../Resources/performanceMetrics.js` which collects:

- **Core Timing Metrics** (in milliseconds):
  - `loadComplete`: Total page load time
  - `domComplete`: DOM completion time
  - `domContentLoaded`: DOM content loaded time
  - `domInteractive`: DOM interactive time

- **Paint Metrics**:
  - `fcp` / `firstContentfulPaint`: First Contentful Paint
  - `largestContentfulPaint`: Largest Contentful Paint (if available)

- **Network Metrics**:
  - `ttfb` / `timeToFirstByte`: Time to First Byte
  - `responseTime`: Server response time
  - `serverTime`: Server processing time

- **Size Metrics** (in bytes):
  - `transferSize`: Total transfer size
  - `encodedBodySize`: Encoded body size
  - `decodedBodySize`: Decoded body size

- **Resource Metrics**:
  - `resourceCount`: Number of resources
  - `totalResourcesSize`: Total size of all resources

- **Additional Metadata**:
  - `protocol`: Network protocol used
  - `redirectCount`: Number of redirects
  - `navigationType`: Type of navigation

## Troubleshooting

1. **Safari Driver Issues**: Ensure Safari's Remote Automation is enabled
2. **Permission Issues**: The script may require permission to control Safari
3. **Script Not Found**: Verify the performance metrics script exists at `../Resources/performanceMetrics.js`