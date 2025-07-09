def runPlaywrightTests(resultDir, browser, testFiles) {
    try {
        timeout(120) {
            def testFilesArg = testFiles.join(' ')
            sh """
                rm -f results.xml
                PLAYWRIGHT_JUNIT_OUTPUT_NAME=results.xml npx playwright test ${testFilesArg} --project ${browser} --reporter=junit || true
            """
        }
    } finally {
        def summary = junit skipMarkingBuildUnstable: true, skipPublishingChecks: true, testResults: 'results.xml'
        return summary
    }
}

def withEnvFile(envfile, Closure cb) {
    def props = readProperties(file: envfile)
    withEnv(props.collect{ entry -> "${entry.key}=${entry.value}" }) {
        cb()
    }
}

def getModifiedFiles() {
    if (env.CHANGE_ID) {
        def changedFiles = sh(script: "git diff --name-only origin/${env.CHANGE_TARGET} HEAD", returnStdout: true).trim()
        return changedFiles.split("\n")
    } else {
        return []
    }
}

def getTestsToRun(modifiedFiles) {
    def testsToRun = []

    // Run any modified test files
    for (file in modifiedFiles) {
        if (file.startsWith("tests/") && file.endsWith(".spec.ts")) {
            testsToRun.add(file)
        }
    }

    // Run the corresponding test file for any modified rule file
    for (file in modifiedFiles) {
        if (file.startsWith("rules/autoconsent/") && file.endsWith(".json")) {
            def fileName = file.substring("rules/autoconsent/".length())
            def baseName = fileName.substring(0, fileName.lastIndexOf(".json"))
            def testFile = "tests/${baseName}.spec.ts"

            if (fileExists(testFile) && !testsToRun.contains(testFile)) {
                testsToRun.add(testFile)
            }
        }
    }

    return testsToRun
}

pipeline {
    agent { label 'autoconsent-crawler' }
    parameters {
        string(name: 'TEST_RESULT_ROOT', defaultValue: '/mnt/efs/users/smacbeth/autoconsent/ci', description: 'Where test results and configuration are stored')
        choice(name: 'BROWSER', choices: ['chrome', 'webkit', 'iphoneSE', 'firefox'], description: 'Browser')
        string(name: 'BRANCH', defaultValue: 'main', description: 'Branch or PR to checkout (e.g. pr/123)')
    }
    environment {
        NODENV_VERSION = "16.16.0"
        NODENV_ROOT = "/opt/nodeenv"
        PATH = "/opt/nodenv/shims:/opt/nodenv/bin:$PATH"
    }
    stages {
        stage('Checkout') {
            when {
                expression {
                    // skip the BRANCH variable if this is running in a multibranch job
                    return env.BRANCH_NAME == null
                }
            }
            steps {
                checkout([$class: 'GitSCM', branches: [[name: "${params.BRANCH}"]],
                    extensions: [[$class: 'LocalBranch']],
                    userRemoteConfigs: [[refspec: "+refs/pull/*/head:refs/remotes/origin/pr/*", credentialsId: 'autoconsent-rw', url: 'https://github.com/duckduckgo/autoconsent.git']]])
            }
        }

        stage('Build') {
            steps {
                sh '''
                npm ci
                npx playwright install
                '''
                script {
                    if (env.BRANCH_NAME == null) {
                        currentBuild.description = "${params.BRANCH} - ${params.BROWSER}"
                    } else {
                        currentBuild.description = "${env.GIT_COMMIT}"
                    }
                }
            }
        }

        stage('Test') {
            steps {
                script {
                    def testsFailed = 0
                    def testsTotal = 0

                    def modifiedFiles = getModifiedFiles()
                    echo "Modified files: ${modifiedFiles.join(', ')}"

                    def testsToRun = getTestsToRun(modifiedFiles)
                    echo "Tests to run: ${testsToRun.join(', ')}"

                    if (testsToRun.isEmpty()) {
                        echo "No tests to run for this change"
                    } else {
                        def testEnvs = [
                            "${params.TEST_RESULT_ROOT}/de.env",
                            "${params.TEST_RESULT_ROOT}/us.env",
                            "${params.TEST_RESULT_ROOT}/gb.env"
                        ]
                        for (testEnv in testEnvs) {
                            withEnvFile(testEnv) {
                                def summary = runPlaywrightTests(params.TEST_RESULT_ROOT, params.BROWSER, testsToRun)
                                testsFailed += summary.failCount
                                testsTotal += summary.totalCount
                            }
                        }
                    }

                    def status = 'SUCCESS'
                    def description = "No tests to run"

                    if (testsTotal > 0) {
                        description = "${testsFailed}/${testsTotal} failed"
                        if (testsFailed > 0) {
                            status = 'FAILURE'
                        }
                    }

                    githubNotify(
                            account: 'duckduckgo',
                            repo: 'autoconsent',
                            context: 'Tests / Changed files',
                            sha: "${env.GIT_COMMIT}",
                            description: description,
                            status: status,
                            credentialsId: 'autoconsent-rw'
                    )
                }
            }
        }
    }
}
