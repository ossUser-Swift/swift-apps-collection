import SwiftUI
import WebKit

// UIViewRepresentable wrapper for WKWebView to load local HTML
struct HTMLWebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

struct ContentView: View {
    // Find HTML files in bundle
    private var htmlFiles: [URL] {
        Bundle.main.urls(forResourcesWithExtension: "html", subdirectory: nil) ?? []
    }
    
    var body: some View {
        Group {
            if htmlFiles.count == 1, let url = htmlFiles.first {
                // Show the single HTML file fullscreen
                HTMLWebView(url: url)
                    .edgesIgnoringSafeArea(.all)
            } else {
                // Show black screen with message if zero or multiple HTML files found
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    Text("only one html file please!")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
    }
}

