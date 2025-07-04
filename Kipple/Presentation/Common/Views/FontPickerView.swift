//
//  FontPickerView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI
import AppKit

struct FontPickerView: NSViewRepresentable {
    @Binding var selectedFontName: String
    @Binding var selectedFontSize: CGFloat
    let onFontSelected: ((String, CGFloat) -> Void)?
    
    init(
        selectedFontName: Binding<String>,
        selectedFontSize: Binding<CGFloat>,
        onFontSelected: ((String, CGFloat) -> Void)? = nil
    ) {
        self._selectedFontName = selectedFontName
        self._selectedFontSize = selectedFontSize
        self.onFontSelected = onFontSelected
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = "フォントを選択..."
        button.bezelStyle = .rounded
        button.target = context.coordinator
        button.action = #selector(Coordinator.showFontPanel(_:))
        return button
    }
    
    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = "\(selectedFontName) - \(Int(selectedFontSize))pt"
    }
    
    class Coordinator: NSObject {
        let parent: FontPickerView
        
        init(_ parent: FontPickerView) {
            self.parent = parent
            super.init()
            
            // フォントパネルの変更を監視
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(fontChanged(_:)),
                name: NSNotification.Name("NSFontPanelDidChangeNotification"),
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func showFontPanel(_ sender: Any?) {
            let fontManager = NSFontManager.shared
            let fontPanel = fontManager.fontPanel(true)
            
            // 現在のフォントを設定
            if let currentFont = NSFont(name: parent.selectedFontName, size: parent.selectedFontSize) {
                fontManager.setSelectedFont(currentFont, isMultiple: false)
            }
            
            fontPanel?.makeKeyAndOrderFront(sender)
        }
        
        @objc func fontChanged(_ notification: Notification) {
            guard let fontManager = notification.object as? NSFontManager else { return }
            
            let newFont = fontManager.convert(.systemFont(ofSize: 12))
            parent.selectedFontName = newFont.fontName
            parent.selectedFontSize = newFont.pointSize
            parent.onFontSelected?(newFont.fontName, newFont.pointSize)
        }
    }
}

// MARK: - Unified Font Manager View  
struct UnifiedFontManagerView: View {
    @Binding var fontList: [String]
    let availableFonts: [String]
    
    @State private var showingAddFontSheet = false
    @State private var selectedFontToAdd = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("フォント優先順位")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    selectedFontToAdd = availableFonts.first { !fontList.contains($0) } ?? ""
                    showingAddFontSheet = true
                }, label: {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                })
                .buttonStyle(PlainButtonStyle())
                .disabled(fontList.count >= availableFonts.count)
            }
            
            VStack(spacing: 4) {
                ForEach(Array(fontList.enumerated()), id: \.offset) { index, fontName in
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fontName)
                                .font(.custom(fontName, size: 12))
                            
                            if index == 0 {
                                Text("プライマリフォント")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            } else {
                                Text("フォールバック #\(index)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // 上下移動ボタン
                        HStack(spacing: 2) {
                            Button(action: { moveFont(from: index, by: -1) }) {
                                Image(systemName: "chevron.up")
                                    .font(.caption)
                            }
                            .disabled(index == 0)
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: { moveFont(from: index, by: 1) }) {
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .disabled(index == fontList.count - 1)
                            .buttonStyle(PlainButtonStyle())
                        }
                        .foregroundColor(.secondary)
                        
                        Button(action: { removeFont(at: index) }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(fontList.count <= 1) // 最低1つは必要
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(index == 0 ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                }
            }
            
            if fontList.isEmpty {
                Text("フォントが設定されていません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showingAddFontSheet) {
            VStack(spacing: 16) {
                Text("フォントを追加")
                    .font(.headline)
                
                FontListPicker(
                    selectedFont: $selectedFontToAdd,
                    availableFonts: availableFonts.filter { !fontList.contains($0) },
                    title: "フォントを選択"
                )
                
                HStack {
                    Button("キャンセル") {
                        showingAddFontSheet = false
                    }
                    .keyboardShortcut(.escape)
                    
                    Spacer()
                    
                    Button("追加") {
                        if !selectedFontToAdd.isEmpty {
                            fontList.append(selectedFontToAdd)
                        }
                        showingAddFontSheet = false
                    }
                    .keyboardShortcut(.return)
                    .disabled(selectedFontToAdd.isEmpty)
                }
            }
            .padding()
            .frame(width: 400)
        }
    }
    
    private func moveFont(from index: Int, by offset: Int) {
        let newIndex = index + offset
        guard newIndex >= 0 && newIndex < fontList.count else { return }
        fontList.swapAt(index, newIndex)
    }
    
    private func removeFont(at index: Int) {
        guard fontList.count > 1 else { return } // 最低1つは必要
        fontList.remove(at: index)
    }
}

// MARK: - Font List Picker
struct FontListPicker: View {
    @Binding var selectedFont: String
    let availableFonts: [String]
    let title: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: $selectedFont) {
                ForEach(availableFonts, id: \.self) { fontName in
                    HStack {
                        Text(fontName)
                            .font(.custom(fontName, size: 12))
                        Spacer()
                        Text("ABC abc 123")
                            .font(.custom(fontName, size: 12))
                            .foregroundColor(.secondary)
                    }
                    .tag(fontName)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Fallback Font Manager View
struct FallbackFontManagerView: View {
    @Binding var fallbackFonts: [String]
    let availableFonts: [String]
    
    @State private var showingAddFontSheet = false
    @State private var selectedFontToAdd = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("フォールバックフォント")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    selectedFontToAdd = availableFonts.first ?? ""
                    showingAddFontSheet = true
                }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            VStack(spacing: 4) {
                ForEach(Array(fallbackFonts.enumerated()), id: \.offset) { index, fontName in
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        
                        Text(fontName)
                            .font(.custom(fontName, size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // 上下移動ボタン
                        HStack(spacing: 2) {
                            Button(action: { moveFont(from: index, by: -1) }) {
                                Image(systemName: "chevron.up")
                                    .font(.caption)
                            }
                            .disabled(index == 0)
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: { moveFont(from: index, by: 1) }) {
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .disabled(index == fallbackFonts.count - 1)
                            .buttonStyle(PlainButtonStyle())
                        }
                        .foregroundColor(.secondary)
                        
                        Button(action: { removeFont(at: index) }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                }
            }
            
            if fallbackFonts.isEmpty {
                Text("フォールバックフォントが設定されていません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showingAddFontSheet) {
            VStack(spacing: 16) {
                Text("フォールバックフォントを追加")
                    .font(.headline)
                
                FontListPicker(
                    selectedFont: $selectedFontToAdd,
                    availableFonts: availableFonts.filter { !fallbackFonts.contains($0) },
                    title: "フォントを選択"
                )
                
                HStack {
                    Button("キャンセル") {
                        showingAddFontSheet = false
                    }
                    .keyboardShortcut(.escape)
                    
                    Spacer()
                    
                    Button("追加") {
                        if !selectedFontToAdd.isEmpty {
                            fallbackFonts.append(selectedFontToAdd)
                        }
                        showingAddFontSheet = false
                    }
                    .keyboardShortcut(.return)
                    .disabled(selectedFontToAdd.isEmpty)
                }
            }
            .padding()
            .frame(width: 400)
        }
    }
    
    private func moveFont(from index: Int, by offset: Int) {
        let newIndex = index + offset
        guard newIndex >= 0 && newIndex < fallbackFonts.count else { return }
        fallbackFonts.swapAt(index, newIndex)
    }
    
    private func removeFont(at index: Int) {
        fallbackFonts.remove(at: index)
    }
}
