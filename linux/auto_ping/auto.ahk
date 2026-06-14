#Requires AutoHotkey v2.0
#SingleInstance Force

; ====== CONFIGURATION ======
StartupDelay := 5               ; 5-second countdown to focus your window
CycleInterval := 30 * 60        ; 30 minutes between cycles (in seconds)
TotalCycles := 9                ; 9 cycles of 30 mins = 4.5 hours of W presses
DelayBeforeEnter := 200          ; Delay between key and Enter (milliseconds)
; ============================

; Initial 5-second delay to let you click into your target window
Sleep(StartupDelay * 1000)

; 1. Right away: Send "Start" + Enter
Send("Start")
Sleep(DelayBeforeEnter)
Send("{Enter}")

; 2. Loop for the next 4.5 hours (9 intervals of 30 minutes) sending "W"
Loop TotalCycles {
    Sleep(CycleInterval * 1000) ; Wait 30 minutes
    
    Send("W")
    Sleep(DelayBeforeEnter)
    Send("{Enter}")
}

; 3. The final 30 minutes: Wait and send "End" instead of W
Sleep(CycleInterval * 1000)    ; Wait the final 30 minutes

Send("End")
Sleep(DelayBeforeEnter)
Send("{Enter}")

ExitApp

; Emergency Stop: Press Escape at any time to instantly kill the script
Esc::ExitApp