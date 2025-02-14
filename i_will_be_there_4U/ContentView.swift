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
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "heart")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .foregroundColor(.green)
                    
                    Text("Chat analyser")
                        .font(.system(size: 32, weight: .bold))
                    
                    Text("Reads the bond and creates memory cards")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 100)
                
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Export the chat from whatsapp.")
                    Text("2. Select without attachment for better\n    processing.")
                    Text("3. Convert the ZIP file to .txt file.")
                    Text("4. Open Chat analyser & upload the\n    chat.txt here.")
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // File Status and Upload
                if !fileContent.isEmpty {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(fileName)
                                .font(.headline)
                            Button(action: {
                                isFilePickerPresented = true
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.green)
                                    .font(.system(size: 16))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text("Chat uploaded successfully!")
                            .foregroundColor(.green)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 8)
                } else {
                    Button(action: {
                        isFilePickerPresented = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up.fill")
                            Text("Upload Chat")
                        }
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .background(Color.green)
                    .cornerRadius(25)
                }
                
                // Create Memory Button
                if !fileContent.isEmpty {
                    Button(action: {
                        processWithGemini()
                    }) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("Create Memory")
                        }
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .background(Color.green)
                    .cornerRadius(25)
                    .disabled(isProcessing)
                }
                
                // Processing Status
                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                        
                        Text("Creating your memory...")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 8)
                }
                
                // Response Display
                if !geminiResponse.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your Memory Card")
                            .font(.title2)
                            .bold()
                            .padding(.horizontal)
                        
                        Text(geminiResponse)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Spacer(minLength: 40)
                Spacer()
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
            .frame(minHeight: UIScreen.main.bounds.height)
        }
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
            
            progressCallback("Reading the converstions \(index + 1)/\(textChunks.count)...")
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
