import SwiftUI

public struct ApprovalDetailView: View {
    let request: ApprovalRequest
    
    @EnvironmentObject private var viewModel: ApprovalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var permissionScope = "turn"
    @State private var selectedOptions: [String: String] = [:]
    @State private var answers: [String: String] = [:]
    @State private var otherAnswers: [String: String] = [:]
    @State private var formValues: [String: String] = [:]
    @State private var booleanValues: [String: Bool] = [:]
    @State private var multiSelectValues: [String: Set<String>] = [:]
    
    public init(request: ApprovalRequest) {
        self.request = request
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            CompactWatchHeader("Approval") {
                Text(request.toolName)
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundColor(toolColor(request.toolName))
                    .lineLimit(1)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: toolIcon(request.toolName))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(toolColor(request.toolName))
                        Text(formattedTime(request.timestamp))
                            .font(.system(size: 8, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Action")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)

                        Text(request.details)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(request.toolName == "run_command" ? .green : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(5)
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)

                    if request.responseMethod == "item/permissions/requestApproval" {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Grant access for")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                            Picker("Scope", selection: $permissionScope) {
                                Text("This turn").tag("turn")
                                Text("Session").tag("session")
                            }
                        }
                    }

                    if request.responseMethod == "item/tool/requestUserInput" {
                        ForEach(request.questions) { question in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(question.question)
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .fixedSize(horizontal: false, vertical: true)

                                if let options = question.options, !options.isEmpty {
                                    Picker(question.header, selection: selectionBinding(for: question)) {
                                        Text("Choose…").tag("")
                                        ForEach(options) { option in
                                            Text(option.label).tag(option.label)
                                        }
                                        if question.isOther {
                                            Text("Other").tag("__other__")
                                        }
                                    }
                                    if let selected = selectedOptions[question.id],
                                       let option = options.first(where: { $0.label == selected }),
                                       !option.description.isEmpty {
                                        Text(option.description)
                                            .font(.system(size: 8, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                    if question.isOther && selectedOptions[question.id] == "__other__" {
                                        answerField("Your answer", question: question, binding: otherBinding(for: question))
                                    }
                                } else {
                                    answerField(question.header, question: question, binding: answerBinding(for: question))
                                }
                            }
                            .padding(4)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }

                    if request.responseMethod == "mcpServer/elicitation/request" {
                        if let url = elicitationURL {
                            Link(destination: url) {
                                Label("Open secure request", systemImage: "arrow.up.right.square")
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                            }
                        }
                        if request.elicitationMode == "url" {
                            Text("Open the secure link, then approve to finish.")
                                .font(.system(size: 8, design: .rounded))
                                .foregroundColor(.secondary)
                        } else if request.elicitationMode == "openai/userVerification" {
                            Text("This needs a verification proof Wristex cannot provide. Use a Codex client that supports device verification.")
                                .font(.system(size: 8, design: .rounded))
                                .foregroundColor(.orange)
                        } else if !supportedFormModes.contains(request.elicitationMode ?? "") {
                            Text("This request type cannot be approved from Wristex.")
                                .font(.system(size: 8, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        ForEach(request.formFields) { field in
                            elicitationField(field)
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 8, design: .rounded))
                            .foregroundColor(.red)
                    }

                    HStack(spacing: 4) {
                        Button {
                            Task {
                                if await viewModel.respond(id: request.id, approve: false) {
                                    dismiss()
                                }
                            }
                        } label: {
                            Label(request.responseMethod == "item/tool/requestUserInput" ? "Skip" : "Deny", systemImage: "xmark")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, height: 30)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(viewModel.isLoading)

                        Button {
                            Task {
                                if await viewModel.respond(
                                    id: request.id,
                                    approve: true,
                                    permissionScope: permissionScope,
                                    answers: responseAnswers,
                                    elicitationContent: elicitationContent
                                ) {
                                    dismiss()
                                }
                            }
                        } label: {
                            Label(approveLabel, systemImage: "checkmark")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, height: 30)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .background(Color.emerald.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(viewModel.isLoading || !canApprove)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var approveLabel: String {
        request.responseMethod == "item/tool/requestUserInput" ? "Submit" : "Approve"
    }

    private var responseAnswers: [String: [String]] {
        var result: [String: [String]] = [:]
        for question in request.questions {
            let value: String
            if let options = question.options, !options.isEmpty {
                if selectedOptions[question.id] == "__other__" {
                    value = otherAnswers[question.id] ?? ""
                } else {
                    value = selectedOptions[question.id] ?? ""
                }
            } else {
                value = answers[question.id] ?? ""
            }
            let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanValue.isEmpty {
                result[question.id] = [cleanValue]
            }
        }
        return result
    }

    private var canApprove: Bool {
        if request.responseMethod == "item/tool/requestUserInput", request.isBlocking {
            return !request.questions.isEmpty && request.questions.allSatisfy {
                !(responseAnswers[$0.id]?.isEmpty ?? true)
            }
        }
        guard request.responseMethod == "mcpServer/elicitation/request" else { return true }
        if request.elicitationMode == "url" { return elicitationURL != nil }
        guard let mode = request.elicitationMode, supportedFormModes.contains(mode) else { return false }
        return request.formFields.filter(\.required).allSatisfy { field in
            if field.kind == "boolean" { return true }
            return elicitationContent[field.name] != nil
        }
    }

    private var supportedFormModes: [String] {
        ["form", "openai/form", "openaiForm"]
    }

    private var elicitationContent: [String: Any] {
        var result: [String: Any] = [:]
        for field in request.formFields {
            switch field.kind {
            case "boolean":
                if field.required || field.defaultValue != nil || booleanValues[field.name] != nil {
                    result[field.name] = booleanValues[field.name] ?? (field.defaultValue == "true" || field.defaultValue == "1")
                }
            case "number":
                let value = formValues[field.name] ?? field.defaultValue ?? ""
                if let number = Double(value) { result[field.name] = number }
            case "integer":
                let value = formValues[field.name] ?? field.defaultValue ?? ""
                if let number = Int(value) { result[field.name] = number }
            case "singleSelect":
                let value = formValues[field.name] ?? field.defaultValue ?? ""
                if !value.isEmpty { result[field.name] = value }
            case "multiSelect":
                let values = multiSelectValues[field.name] ?? Set((field.defaultValue ?? "").split(separator: ",").map { String($0) })
                if !values.isEmpty { result[field.name] = Array(values).sorted() }
            case "array":
                let value = formValues[field.name] ?? field.defaultValue ?? ""
                let values = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if !values.isEmpty { result[field.name] = values }
            default:
                let value = (formValues[field.name] ?? field.defaultValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { result[field.name] = value }
            }
        }
        return result
    }

    private var elicitationURL: URL? {
        guard let rawURL = request.elicitationURL,
              let url = URL(string: rawURL),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    @ViewBuilder
    private func elicitationField(_ field: ApprovalFormField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !field.description.isEmpty {
                Text(field.description)
                    .font(.system(size: 8, design: .rounded))
                    .foregroundColor(.secondary)
            }

            if field.kind == "boolean" {
                Toggle(field.title, isOn: booleanBinding(for: field))
                    .font(.system(size: 9, design: .rounded))
            } else if field.kind == "singleSelect", let options = field.options {
                Picker(field.title, selection: formBinding(for: field)) {
                    Text("Choose…").tag("")
                    ForEach(options) { option in
                        Text(option.label).tag(option.description)
                    }
                }
            } else if field.kind == "multiSelect", let options = field.options {
                Text(field.title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                ForEach(options) { option in
                    Toggle(option.label, isOn: multiSelectBinding(for: field, value: option.description))
                        .font(.system(size: 8, design: .rounded))
                }
            } else if field.isSecret {
                SecureField(field.title, text: formBinding(for: field))
                    .font(.system(size: 10, design: .rounded))
            } else {
                TextField(field.title, text: formBinding(for: field), axis: .vertical)
                    .font(.system(size: 10, design: .rounded))
                    .lineLimit(1...3)
                    .autocorrectionDisabled()
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08))
        .cornerRadius(6)
    }

    private func formBinding(for field: ApprovalFormField) -> Binding<String> {
        Binding(
            get: { formValues[field.name] ?? field.defaultValue ?? "" },
            set: { formValues[field.name] = $0 }
        )
    }

    private func booleanBinding(for field: ApprovalFormField) -> Binding<Bool> {
        Binding(
            get: { booleanValues[field.name] ?? (field.defaultValue == "true" || field.defaultValue == "1") },
            set: { booleanValues[field.name] = $0 }
        )
    }

    private func multiSelectBinding(for field: ApprovalFormField, value: String) -> Binding<Bool> {
        Binding(
            get: { (multiSelectValues[field.name] ?? Set((field.defaultValue ?? "").split(separator: ",").map { String($0) })).contains(value) },
            set: { isSelected in
                var selection = multiSelectValues[field.name] ?? Set((field.defaultValue ?? "").split(separator: ",").map { String($0) })
                if isSelected { selection.insert(value) } else { selection.remove(value) }
                multiSelectValues[field.name] = selection
            }
        )
    }

    private func selectionBinding(for question: ApprovalQuestion) -> Binding<String> {
        Binding(
            get: { selectedOptions[question.id] ?? "" },
            set: { selectedOptions[question.id] = $0 }
        )
    }

    private func answerBinding(for question: ApprovalQuestion) -> Binding<String> {
        Binding(
            get: { answers[question.id] ?? "" },
            set: { answers[question.id] = $0 }
        )
    }

    private func otherBinding(for question: ApprovalQuestion) -> Binding<String> {
        Binding(
            get: { otherAnswers[question.id] ?? "" },
            set: { otherAnswers[question.id] = $0 }
        )
    }

    @ViewBuilder
    private func answerField(_ title: String, question: ApprovalQuestion, binding: Binding<String>) -> some View {
        if question.isSecret {
            SecureField(title, text: binding)
                .font(.system(size: 10, design: .rounded))
        } else {
            TextField(title, text: binding, axis: .vertical)
                .font(.system(size: 10, design: .rounded))
                .lineLimit(1...3)
                .autocorrectionDisabled()
        }
    }
    
    private func toolIcon(_ name: String) -> String {
        switch name {
        case "run_command": return "terminal.fill"
        case "write_file", "replace_file_content", "multi_replace_file_content": return "doc.text.fill"
        case "read_file": return "doc.text.magnifyingglass"
        case "search_web": return "globe"
        default: return "questionmark.key.filled"
        }
    }
    
    private func toolColor(_ name: String) -> Color {
        switch name {
        case "run_command": return .red
        case "write_file", "replace_file_content", "multi_replace_file_content": return .orange
        case "read_file": return .blue
        case "search_web": return .purple
        default: return .secondary
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ApprovalDetailView_Previews: PreviewProvider {
    public static var previews: some View {
        let request = ApprovalRequest(id: "appr-1", toolName: "run_command", details: "git commit -m 'feat: biometrics'", status: "pending", timestamp: Date())
        let mockVm = ApprovalViewModel()
        return ApprovalDetailView(request: request)
            .environmentObject(mockVm)
    }
}
