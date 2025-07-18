//
//  ClipboardService+AutoClear.swift
//  Kipple
//
//  Created by Kipple on 2025/07/17.
//

import Foundation
import Cocoa

// MARK: - Auto-Clear Timer Methods
extension ClipboardService {
    
    @MainActor
    func startAutoClearTimerIfNeeded() {
        guard AppSettings.shared.enableAutoClear else {
            stopAutoClearTimer()
            return
        }
        
        stopAutoClearTimer()
        
        let interval = TimeInterval(AppSettings.shared.autoClearInterval * 60)
        autoClearStartTime = Date()
        
        // Update remaining time immediately
        autoClearRemainingTime = interval
        
        // Create timer that updates every second
        autoClearTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let startTime = self.autoClearStartTime else { return }
            
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = interval - elapsed
            
            if remaining <= 0 {
                Task { @MainActor in
                    self.performAutoClear()
                    self.restartAutoClearTimer()
                }
            } else {
                self.autoClearRemainingTime = remaining
            }
        }
    }
    
    func stopAutoClearTimer() {
        autoClearTimer?.invalidate()
        autoClearTimer = nil
        autoClearStartTime = nil
        autoClearRemainingTime = nil
    }
    
    @MainActor
    private func restartAutoClearTimer() {
        if AppSettings.shared.enableAutoClear {
            startAutoClearTimerIfNeeded()
        }
    }
    
    @MainActor
    private func performAutoClear() {
        // Check if current clipboard content is text
        guard NSPasteboard.general.string(forType: .string) != nil else {
            Logger.shared.log("Skipping auto-clear: current clipboard content is not text")
            return
        }
        
        Logger.shared.log("Performing auto-clear of system clipboard")
        
        // Clear the system clipboard
        NSPasteboard.general.clearContents()
        
        // Update the current clipboard content
        currentClipboardContent = nil
    }
    
    // Called when auto-clear settings change
    func updateAutoClearTimer() {
        Task { @MainActor [weak self] in
            self?.startAutoClearTimerIfNeeded()
        }
    }
}
