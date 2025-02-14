//
//  ContentView.swift
//  i_will_be_there_4U
//
//  Created by Karthik  on 14/02/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var fileContent: String = ""
    @State private var isFilePickerPresented: Bool = false
    @State private var fileName: String = "No file selected"
    @State private var geminiResponse: String = ""
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 22) {
            Text(fileName)
                .font(.headline)
                .padding(.top)
            
            HStack(spacing: 15) {
                Button(action: {
                    isFilePickerPresented = true
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Select .txt File")
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                if !fileContent.isEmpty {
                    Button(action: {
                        processWithGemini()
                    }) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("Process with Gemini")
                        }
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isProcessing)
                }
            }

            if !fileContent.isEmpty {
                Text("File Content:")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                ScrollView {
                    TextEditor(text: .constant(fileContent))
                        .frame(minHeight: 200)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
            
            if isProcessing {
                ProgressView("Processing with Gemini...")
            }
            
            if !geminiResponse.isEmpty {
                Text("Gemini Response:")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                ScrollView {
                    TextEditor(text: .constant(geminiResponse))
                        .frame(minHeight: 200)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .padding()
        .sheet(isPresented: $isFilePickerPresented) {
            DocumentPicker(fileContent: $fileContent, fileName: $fileName)
        }
    }
    
    @MainActor
    private func processWithGemini() {
        isProcessing = true
        errorMessage = nil
        geminiResponse = ""
        
        // Split content into chunks if it's too large
        let chunks = splitTextIntoChunks(text: fileContent, maxChunkSize: 100000)
        
        Task {
            do {
                let response = try await callGeminiAPI(textChunks: chunks) { progress in
                    Task { @MainActor in
                        geminiResponse = progress
                    }
                }
                await MainActor.run {
                    geminiResponse = response
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var fileContent: String
    @Binding var fileName: String

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.plainText], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ documentPicker: DocumentPicker) {
            self.parent = documentPicker
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            do {
                let fileContent = try String(contentsOf: url, encoding: .utf8)
                DispatchQueue.main.async { [self] in
                    self.parent.fileContent = fileContent
                    self.parent.fileName = url.lastPathComponent
                }
            } catch {
                print("Error reading file: \(error)")
                DispatchQueue.main.async { [self] in
                    self.parent.fileContent = "Error reading file: \(error.localizedDescription)"
                    self.parent.fileName = "Error loading file"
                }
            }
        }
    }
}

extension ContentView {
    // Helper function to split text into smaller chunks
    func splitTextIntoChunks(text: String, maxChunkSize: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = text.startIndex
        
        while currentIndex < text.endIndex {
            let endIndex = text.index(currentIndex, offsetBy: maxChunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[currentIndex..<endIndex])
            chunks.append(chunk)
            currentIndex = endIndex
        }
        
        return chunks
    }

    func callGeminiAPI(textChunks: [String], progressCallback: (String) -> Void) async throws -> String {
        let apiKey = "AIzaSyCymLCmKtrxLDL0RcS5EGWHu0K9RVBGo6M"
        var responses: [String] = []
        
        progressCallback("Starting to process \(textChunks.count) chunks...")
        
        for (index, chunk) in textChunks.enumerated() {
            // Add delay between chunks
            if index > 0 {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
            }
            
            // Split into smaller chunks if needed
            let subChunks = splitTextIntoChunks(text: chunk, maxChunkSize: 30000)
            
            progressCallback("Processing chunk \(index + 1)/\(textChunks.count)...")
            for (subIndex, subChunk) in subChunks.enumerated() {
                if subIndex > 0 {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                }
                
                let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.0-pro:generateContent?key=\(apiKey)")
                guard let url = url else { throw URLError(.badURL) }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let requestBody: [String: Any] = [
                    "contents": [
                        [
                            "parts": [
                                ["text": "Analyze and summarize this text: \(subChunk)"]
                            ]
                        ]
                    ],
                    "generationConfig": [
                        "temperature": 0.3,
                        "maxOutputTokens": 2048
                    ]
                ]
                
                let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
                request.httpBody = jsonData
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                if httpResponse.statusCode != 200 {
                    // Print the error response for debugging
                    let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    print("API Error: \(errorJson ?? [:])")
                    
                    if httpResponse.statusCode == 429 {
                        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 second delay
                        continue // Retry this chunk
                    } else {
                        throw URLError(.badServerResponse)
                    }
                }
                
                let responseJson = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let candidates = responseJson?["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    responses.append(text)
                }
            }
        }
        
        return responses.joined(separator: "\n\n")
    let semaphore = DispatchSemaphore(value: 5) // Increased concurrent calls
    
    // Process chunks concurrently
    try await withThrowingTaskGroup(of: String.self) { group in
        for chunk in textChunks {
            group.addTask {
                // Wait for semaphore
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        semaphore.wait()
                        continuation.resume()
                    }
                }
                
                defer { semaphore.signal() } // Release semaphore when done
                
                let apiUrl = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!
                var request = URLRequest(url: apiUrl)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // Simplified request format
                let requestBody: [String: Any] = [
                    "contents": [
                        [
                            "parts": [
                                ["text": chunk]
                            ]
                        ]
                    ]
                ]
                
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                // Print request body for debugging
                print("Request Body: \(String(describing: requestBody))")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Print HTTP response details
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP Status Code: \(httpResponse.statusCode)")
                    print("Response Headers: \(httpResponse.allHeaderFields)")
                }
                
                // Print raw response for debugging
                if let rawResponse = String(data: data, encoding: .utf8) {
                    print("Raw API Response: \(rawResponse)")
                }
                
                let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                print("Parsed JSON Response: \(String(describing: jsonResponse))")
                
                if let error = jsonResponse?["error"] as? [String: Any] {
                    throw NSError(domain: "GeminiAPI", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: "API Error: \(error)"])
                }
                
                guard let candidates = jsonResponse?["candidates"] as? [[String: Any]],
                      !candidates.isEmpty else {
                    throw NSError(domain: "GeminiAPI", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: "No candidates in response. Full response: \(String(describing: jsonResponse))"])
                }
                
                guard let content = candidates[0]["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      !parts.isEmpty else {
                    throw NSError(domain: "GeminiAPI", code: -2, 
                                 userInfo: [NSLocalizedDescriptionKey: "Invalid content format"])
                }
                
                guard let text = parts[0]["text"] as? String else {
                    throw NSError(domain: "GeminiAPI", code: -3, 
                                 userInfo: [NSLocalizedDescriptionKey: "No text in response"])
                }
                
                return text
            }
        }
        
        // Collect responses in order
        for try await response in group {
            responses.append(response)
        }
    }
    
    return responses.joined(separator: "\n\n")
}

    func convertToJson(text: String) -> String {
        let jsonObject: [String: Any] = ["text": text]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            } else {
                return "Error: Could not convert JSON data to string"
            }
        } catch {
            print("Error converting to JSON: \(error)")
            return "Error: Could not convert to JSON"
        }
    }
}

extension String {
    func chunked(into size: Int) -> [String] {
        return stride(from: 0, to: count, by: size).map {
            let start = index(startIndex, offsetBy: $0)
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            return String(self[start..<end])
        }
    }
}

#Preview {
    ContentView()
}
