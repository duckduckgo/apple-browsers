//
//  ContextualSuggestionUserText.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

extension UserText {

    public static let aiChatSuggestionSummarizePageLabel = NSLocalizedString("duckai.suggestion.summarize-page.label", value: "Summarize this page", comment: "Suggested prompt chip: summarize the current page")
    public static let aiChatSuggestionSummarizePagePrompt = NSLocalizedString("duckai.suggestion.summarize-page.prompt", value: "Summarize this page.", comment: "Suggested prompt submitted text: summarize the current page")

    public static let aiChatSuggestionTranslatePageLabel = NSLocalizedString("duckai.suggestion.translate-page.label", value: "Translate this page", comment: "Suggested prompt chip: translate the current page")
    public static let aiChatSuggestionTranslatePagePrompt = NSLocalizedString("duckai.suggestion.translate-page.prompt", value: "Translate this page into %@.", comment: "Suggested prompt submitted text: translate the page. %@ is replaced with the name of the user's language.")

    public static let aiChatSuggestionKeyTakeawaysLabel = NSLocalizedString("duckai.suggestion.key-takeaways.label", value: "What are the key takeaways?", comment: "Suggested prompt chip: key takeaways of an article")
    public static let aiChatSuggestionKeyTakeawaysPrompt = NSLocalizedString("duckai.suggestion.key-takeaways.prompt", value: "What are the key takeaways from this article?", comment: "Suggested prompt submitted text: key takeaways of an article")

    public static let aiChatSuggestionExplainSimplyLabel = NSLocalizedString("duckai.suggestion.explain-simply.label", value: "Explain this simply", comment: "Suggested prompt chip: explain the content simply")
    public static let aiChatSuggestionExplainSimplyPrompt = NSLocalizedString("duckai.suggestion.explain-simply.prompt", value: "Explain this in simple, plain language.", comment: "Suggested prompt submitted text: explain the content simply")

    public static let aiChatSuggestionCounterargumentsLabel = NSLocalizedString("duckai.suggestion.counterarguments.label", value: "What are the counterarguments?", comment: "Suggested prompt chip: counterarguments")
    public static let aiChatSuggestionCounterargumentsPrompt = NSLocalizedString("duckai.suggestion.counterarguments.prompt", value: "What are the main counterarguments or criticisms of this?", comment: "Suggested prompt submitted text: counterarguments")

    public static let aiChatSuggestionRelatedArticlesLabel = NSLocalizedString("duckai.suggestion.related-articles.label", value: "Suggest related articles to explore", comment: "Suggested prompt chip: related articles")
    public static let aiChatSuggestionRelatedArticlesPrompt = NSLocalizedString("duckai.suggestion.related-articles.prompt", value: "Suggest related articles or topics worth exploring next.", comment: "Suggested prompt submitted text: related articles")

    public static let aiChatSuggestionShoppingListLabel = NSLocalizedString("duckai.suggestion.shopping-list.label", value: "Generate a shopping list", comment: "Suggested prompt chip: shopping list from a recipe")
    public static let aiChatSuggestionShoppingListPrompt = NSLocalizedString("duckai.suggestion.shopping-list.prompt", value: "Create a shopping list with quantities from this recipe.", comment: "Suggested prompt submitted text: shopping list from a recipe")

    public static let aiChatSuggestionRecipeNutritionLabel = NSLocalizedString("duckai.suggestion.recipe-nutrition.label", value: "Estimate the nutrition", comment: "Suggested prompt chip: recipe nutrition")
    public static let aiChatSuggestionRecipeNutritionPrompt = NSLocalizedString("duckai.suggestion.recipe-nutrition.prompt", value: "Estimate the nutritional information for this recipe.", comment: "Suggested prompt submitted text: recipe nutrition")

    public static let aiChatSuggestionScaleRecipeLabel = NSLocalizedString("duckai.suggestion.scale-recipe.label", value: "Adjust the servings", comment: "Suggested prompt chip: scale a recipe")
    public static let aiChatSuggestionScaleRecipePrompt = NSLocalizedString("duckai.suggestion.scale-recipe.prompt", value: "Rewrite this recipe scaled for a different number of servings.", comment: "Suggested prompt submitted text: scale a recipe")

    public static let aiChatSuggestionProductProsConsLabel = NSLocalizedString("duckai.suggestion.product-pros-cons.label", value: "What are the pros and cons?", comment: "Suggested prompt chip: product pros and cons")
    public static let aiChatSuggestionProductProsConsPrompt = NSLocalizedString("duckai.suggestion.product-pros-cons.prompt", value: "What are the pros and cons of this product?", comment: "Suggested prompt submitted text: product pros and cons")

    public static let aiChatSuggestionFindAlternativesLabel = NSLocalizedString("duckai.suggestion.find-alternatives.label", value: "Find me alternatives", comment: "Suggested prompt chip: product alternatives")
    public static let aiChatSuggestionFindAlternativesPrompt = NSLocalizedString("duckai.suggestion.find-alternatives.prompt", value: "Suggest some alternatives to this product.", comment: "Suggested prompt submitted text: product alternatives")

    public static let aiChatSuggestionSummarizeVideoLabel = NSLocalizedString("duckai.suggestion.summarize-video.label", value: "Summarize this video", comment: "Suggested prompt chip: summarize a video")
    public static let aiChatSuggestionSummarizeVideoPrompt = NSLocalizedString("duckai.suggestion.summarize-video.prompt", value: "Summarize this video.", comment: "Suggested prompt submitted text: summarize a video")

    public static let aiChatSuggestionVideoKeyPointsLabel = NSLocalizedString("duckai.suggestion.video-key-points.label", value: "What are the key points?", comment: "Suggested prompt chip: video key points")
    public static let aiChatSuggestionVideoKeyPointsPrompt = NSLocalizedString("duckai.suggestion.video-key-points.prompt", value: "What are the key points covered in this video?", comment: "Suggested prompt submitted text: video key points")

    public static let aiChatSuggestionTailorResumeLabel = NSLocalizedString("duckai.suggestion.tailor-resume.label", value: "Tailor my resume", comment: "Suggested prompt chip: tailor a resume to a job")
    public static let aiChatSuggestionTailorResumePrompt = NSLocalizedString("duckai.suggestion.tailor-resume.prompt", value: "Help me tailor my resume for this job.", comment: "Suggested prompt submitted text: tailor a resume to a job")

    public static let aiChatSuggestionInterviewPrepLabel = NSLocalizedString("duckai.suggestion.interview-prep.label", value: "Help me prep for the interview", comment: "Suggested prompt chip: interview prep")
    public static let aiChatSuggestionInterviewPrepPrompt = NSLocalizedString("duckai.suggestion.interview-prep.prompt", value: "What interview questions might come up for this role?", comment: "Suggested prompt submitted text: interview prep")

    public static let aiChatSuggestionCoverLetterLabel = NSLocalizedString("duckai.suggestion.cover-letter.label", value: "Draft a cover letter", comment: "Suggested prompt chip: draft a cover letter")
    public static let aiChatSuggestionCoverLetterPrompt = NSLocalizedString("duckai.suggestion.cover-letter.prompt", value: "Draft a cover letter for this job.", comment: "Suggested prompt submitted text: draft a cover letter")

    public static let aiChatSuggestionEventDetailsLabel = NSLocalizedString("duckai.suggestion.event-details.label", value: "What are the key details?", comment: "Suggested prompt chip: event details")
    public static let aiChatSuggestionEventDetailsPrompt = NSLocalizedString("duckai.suggestion.event-details.prompt", value: "Summarize the key details of this event.", comment: "Suggested prompt submitted text: event details")

    public static let aiChatSuggestionWorthWatchingLabel = NSLocalizedString("duckai.suggestion.worth-watching.label", value: "Is this worth watching?", comment: "Suggested prompt chip: is a movie/show worth watching")
    public static let aiChatSuggestionWorthWatchingPrompt = NSLocalizedString("duckai.suggestion.worth-watching.prompt", value: "Is this worth watching? Give me a spoiler-free take.", comment: "Suggested prompt submitted text: is a movie/show worth watching")

    public static let aiChatSuggestionSimilarTitlesLabel = NSLocalizedString("duckai.suggestion.similar-titles.label", value: "Recommend similar titles", comment: "Suggested prompt chip: similar movies or shows")
    public static let aiChatSuggestionSimilarTitlesPrompt = NSLocalizedString("duckai.suggestion.similar-titles.prompt", value: "Recommend similar movies or shows.", comment: "Suggested prompt submitted text: similar movies or shows")

    public static let aiChatSuggestionCastCrewLabel = NSLocalizedString("duckai.suggestion.cast-crew.label", value: "Cast & Crew", comment: "Suggested prompt chip: cast and crew")
    public static let aiChatSuggestionCastCrewPrompt = NSLocalizedString("duckai.suggestion.cast-crew.prompt", value: "Who are the main cast and crew, and what else are they known for?", comment: "Suggested prompt submitted text: cast and crew")

    public static let aiChatSuggestionSummarizeBookLabel = NSLocalizedString("duckai.suggestion.summarize-book.label", value: "Summarize this book", comment: "Suggested prompt chip: summarize a book")
    public static let aiChatSuggestionSummarizeBookPrompt = NSLocalizedString("duckai.suggestion.summarize-book.prompt", value: "Summarize this book.", comment: "Suggested prompt submitted text: summarize a book")

    public static let aiChatSuggestionSimilarBooksLabel = NSLocalizedString("duckai.suggestion.similar-books.label", value: "Recommend similar books", comment: "Suggested prompt chip: similar books")
    public static let aiChatSuggestionSimilarBooksPrompt = NSLocalizedString("duckai.suggestion.similar-books.prompt", value: "Recommend similar books.", comment: "Suggested prompt submitted text: similar books")

    public static let aiChatSuggestionExplainPaperLabel = NSLocalizedString("duckai.suggestion.explain-paper.label", value: "Explain this paper", comment: "Suggested prompt chip: explain a research paper")
    public static let aiChatSuggestionExplainPaperPrompt = NSLocalizedString("duckai.suggestion.explain-paper.prompt", value: "Explain this research paper in plain language.", comment: "Suggested prompt submitted text: explain a research paper")

    public static let aiChatSuggestionPaperContributionsLabel = NSLocalizedString("duckai.suggestion.paper-contributions.label", value: "What are the key contributions?", comment: "Suggested prompt chip: paper contributions")
    public static let aiChatSuggestionPaperContributionsPrompt = NSLocalizedString("duckai.suggestion.paper-contributions.prompt", value: "What are the key contributions of this paper?", comment: "Suggested prompt submitted text: paper contributions")

    public static let aiChatSuggestionMenuHighlightsLabel = NSLocalizedString("duckai.suggestion.menu-highlights.label", value: "What should I order?", comment: "Suggested prompt chip: restaurant menu highlights")
    public static let aiChatSuggestionMenuHighlightsPrompt = NSLocalizedString("duckai.suggestion.menu-highlights.prompt", value: "What are the must-try dishes here?", comment: "Suggested prompt submitted text: restaurant menu highlights")

    public static let aiChatSuggestionPlaceHoursLabel = NSLocalizedString("duckai.suggestion.place-hours.label", value: "What are the hours & location?", comment: "Suggested prompt chip: place hours and location")
    public static let aiChatSuggestionPlaceHoursPrompt = NSLocalizedString("duckai.suggestion.place-hours.prompt", value: "What are the opening hours, location, and contact details for this place?", comment: "Suggested prompt submitted text: place hours and location")

    public static let aiChatSuggestionPlaceReviewsLabel = NSLocalizedString("duckai.suggestion.place-reviews.label", value: "Is this place any good?", comment: "Suggested prompt chip: place reputation")
    public static let aiChatSuggestionPlaceReviewsPrompt = NSLocalizedString("duckai.suggestion.place-reviews.prompt", value: "Is this place any good? Summarize its reputation based on reviews and ratings.", comment: "Suggested prompt submitted text: place reputation")

    public static let aiChatSuggestionSummarizeThreadLabel = NSLocalizedString("duckai.suggestion.summarize-thread.label", value: "Summarize this discussion", comment: "Suggested prompt chip: summarize a discussion thread")
    public static let aiChatSuggestionSummarizeThreadPrompt = NSLocalizedString("duckai.suggestion.summarize-thread.prompt", value: "Summarize this discussion thread.", comment: "Suggested prompt submitted text: summarize a discussion thread")

    public static let aiChatSuggestionExplainRepoLabel = NSLocalizedString("duckai.suggestion.explain-repo.label", value: "Explain this repo", comment: "Suggested prompt chip: explain a code repository")
    public static let aiChatSuggestionExplainRepoPrompt = NSLocalizedString("duckai.suggestion.explain-repo.prompt", value: "Explain what this repository does and how to use it.", comment: "Suggested prompt submitted text: explain a code repository")

    public static let aiChatSuggestionExplainAnswerLabel = NSLocalizedString("duckai.suggestion.explain-answer.label", value: "Explain the top answer", comment: "Suggested prompt chip: explain the top answer")
    public static let aiChatSuggestionExplainAnswerPrompt = NSLocalizedString("duckai.suggestion.explain-answer.prompt", value: "Explain the accepted answer in simple terms.", comment: "Suggested prompt submitted text: explain the top answer")

    public static let aiChatSuggestionHowtoStepsLabel = NSLocalizedString("duckai.suggestion.howto-steps.label", value: "Walk me through the steps", comment: "Suggested prompt chip: how-to steps")
    public static let aiChatSuggestionHowtoStepsPrompt = NSLocalizedString("duckai.suggestion.howto-steps.prompt", value: "Break this down into clear, numbered steps.", comment: "Suggested prompt submitted text: how-to steps")

    public static let aiChatSuggestionHowtoMaterialsLabel = NSLocalizedString("duckai.suggestion.howto-materials.label", value: "What will I need?", comment: "Suggested prompt chip: how-to materials")
    public static let aiChatSuggestionHowtoMaterialsPrompt = NSLocalizedString("duckai.suggestion.howto-materials.prompt", value: "List the tools, materials, or prerequisites I need for this.", comment: "Suggested prompt submitted text: how-to materials")

    public static let aiChatSuggestionCourseLearnLabel = NSLocalizedString("duckai.suggestion.course-learn.label", value: "What will I learn?", comment: "Suggested prompt chip: course learning outcomes")
    public static let aiChatSuggestionCourseLearnPrompt = NSLocalizedString("duckai.suggestion.course-learn.prompt", value: "What are the key things I will learn from this course?", comment: "Suggested prompt submitted text: course learning outcomes")

    public static let aiChatSuggestionCourseWorthLabel = NSLocalizedString("duckai.suggestion.course-worth.label", value: "Is it worth taking?", comment: "Suggested prompt chip: is a course worth taking")
    public static let aiChatSuggestionCourseWorthPrompt = NSLocalizedString("duckai.suggestion.course-worth.prompt", value: "Based on this page, is this course worth taking?", comment: "Suggested prompt submitted text: is a course worth taking")

    public static let aiChatSuggestionFaqAnswerLabel = NSLocalizedString("duckai.suggestion.faq-answer.label", value: "What does this answer?", comment: "Suggested prompt chip: what an FAQ page answers")
    public static let aiChatSuggestionFaqAnswerPrompt = NSLocalizedString("duckai.suggestion.faq-answer.prompt", value: "What are the main questions this page answers?", comment: "Suggested prompt submitted text: what an FAQ page answers")

    public static let aiChatSuggestionFaqSummaryLabel = NSLocalizedString("duckai.suggestion.faq-summary.label", value: "Summarize the Q&As", comment: "Suggested prompt chip: summarize FAQ Q&As")
    public static let aiChatSuggestionFaqSummaryPrompt = NSLocalizedString("duckai.suggestion.faq-summary.prompt", value: "Summarize the questions and answers on this page.", comment: "Suggested prompt submitted text: summarize FAQ Q&As")

    public static let aiChatSuggestionReviewVerdictLabel = NSLocalizedString("duckai.suggestion.review-verdict.label", value: "What's the verdict?", comment: "Suggested prompt chip: review verdict")
    public static let aiChatSuggestionReviewVerdictPrompt = NSLocalizedString("duckai.suggestion.review-verdict.prompt", value: "What is the overall verdict and rating for this?", comment: "Suggested prompt submitted text: review verdict")

    public static let aiChatSuggestionReviewSummaryLabel = NSLocalizedString("duckai.suggestion.review-summary.label", value: "Sum up the reviews", comment: "Suggested prompt chip: summarize reviews")
    public static let aiChatSuggestionReviewSummaryPrompt = NSLocalizedString("duckai.suggestion.review-summary.prompt", value: "Summarize what the reviews say.", comment: "Suggested prompt submitted text: summarize reviews")

    public static let aiChatSuggestionWhoIsThisLabel = NSLocalizedString("duckai.suggestion.who-is-this.label", value: "Who is this person?", comment: "Suggested prompt chip: person background")
    public static let aiChatSuggestionWhoIsThisPrompt = NSLocalizedString("duckai.suggestion.who-is-this.prompt", value: "Give me a quick background on this person.", comment: "Suggested prompt submitted text: person background")

    public static let aiChatSuggestionPersonBackgroundLabel = NSLocalizedString("duckai.suggestion.person-background.label", value: "Summarize their background", comment: "Suggested prompt chip: summarize a person's background")
    public static let aiChatSuggestionPersonBackgroundPrompt = NSLocalizedString("duckai.suggestion.person-background.prompt", value: "Summarize the background and notable work of this person.", comment: "Suggested prompt submitted text: summarize a person's background")
}
