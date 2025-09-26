//
//  FileImportScreenView.swift
//  
//
//  Created by Graeme Arthur on 26.09.25.
//

struct FileImportScreenView: View {
    @Binding var model: DataImportViewModel
    let title: String
    let dataTypeSelection: DataImport.TypeSelection
    let summaryTypes: Set<DataImport.DataType>
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            VStack(alignment: .center, spacing: 20) {
                if let importSourceImage = model.importSource.importSourceImage {
                    Image(nsImage: importSourceImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                }

                switch dataTypeSelection {
                case .single:
                    Text(UserText.importDataTitle)
                        .font(.title2.weight(.semibold))
                        .padding(.bottom, 20)
                case .multiple:
                    Text("Import from \(model.importSource.importSourceName)")
                        .font(.title2.weight(.semibold))
                        .padding(.bottom, 20)
                }

                VStack(alignment: .leading, spacing: 0) {
                    if !summaryTypes.isEmpty {
                        DataImportSummaryView(model, dataTypes: summaryTypes)
                            .padding(.bottom, 24)
                    }

                    if case .single(let dataType) = dataTypeSelection {
                        // if no data to import
                        if model.summary(for: dataType)?.isEmpty == true
                            || model.error(for: dataType)?.errorType == .noData {
                            DataImportNoDataView(source: model.importSource, dataType: dataType)
                                .padding(.bottom, 24)
                            // if browser importer failed - display error message
                        } else if model.error(for: dataType) != nil {
                            DataImportErrorView(source: model.importSource, dataType: dataType)
                                .padding(.bottom, 24)
                        }
                    }

                    // manual file import instructions for CSV/HTML
                    NewFileImportView(source: model.importSource, dataTypeSelection: dataTypeSelection, isButtonDisabled: model.isSelectFileButtonDisabled) {
                        model.selectFile()
                    } onFileDrop: { url in
                        model.initiateImport(fileURL: url)
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.bottom, 20)
            .padding(.top, 20)
        }
    }

    @ViewBuilder
    private var importSourcePicker: some View {
        DataImportSourcePicker(importSources: model.availableImportSources, selectedSource: model.importSource) { importSource in
            model.update(with: importSource)
        }
        .padding(.bottom, 8)
        .disabled(model.isImportSourcePickerDisabled)
    }

    private func importPickerPanel<Content: View>(_ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            importSourceDataTitle
            importSourcePicker
            content()
        }
        .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.decorationTertiary, lineWidth: 1)
        )
    }

    private var importSourceDataTitle: some View {
        Text(UserText.importDataSourceTitle)
    }
}
