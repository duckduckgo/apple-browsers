// Use TrackerRadarKit for blocking
let trackerDataSet = TrackerDataSet(data: trackerData)
let contentBlocker = ContentBlocker(trackerDataSet: trackerDataSet)

// Apply blocking rules
webView.configuration.userContentController.add(contentBlocker.makeBlockingRules())

