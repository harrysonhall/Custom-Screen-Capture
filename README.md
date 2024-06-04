[June, 4 2024] Discalimer: This is a very rough work in progress, as I am still learning and am new to Swift and working with Apple Frameworks.

This is a custom application for MacOS that creates a native virtual camera and allows you to capture and stream your display to that virtual camera, in a selective manner. It utilizes ScreenCaptureKit to allow you to choose which applications should be included in the stream or not, and Core Media I/O to create a native virtual camera extension.

This was built off of sample code that apple provided for ScreenCaptureKit from their WWDC22, provided here:
https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos

as well as this guys sample code:
https://github.com/ldenoue/cameraextension

^ massive respect to this guy for sharing this code, as 50% of this was built directly off that sample code and literally the only sample code (so far as I know) that provided some basic understanding of how to use the Core Media I/O extensions.


See Apple Session 10022 from WWDC22 for more about Core Media I/O Extensions as well:
https://developer.apple.com/videos/play/wwdc2022/10022/
