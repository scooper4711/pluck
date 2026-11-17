#if os(iOS)
import AppNotices
import Foundation

extension AboutInfo {
    /// Pluck's About screen on the iPad. Its notices, credit and license match `Resources/Credits.html`, which
    /// the Mac's About panel shows.
    static let pluck = AboutInfo(
        appName: "Pluck",
        tagline: "A free app that gets the art, text and stat blocks out of your PDFs.",
        credits: ["WebP images are written with libwebp (chromium.googlesource.com/webm/libwebp), used under "
            + "its BSD license."],
        // A literal URL that is known to parse.
        // swiftlint:disable:next force_unwrapping
        contactURL: URL(string: "https://github.com/scooper4711/pluck/issues")!,
        licenses: [LicenseText(title: "libwebp", text: libwebpLicense)]
    )

    private static let libwebpLicense = """
        Copyright (c) 2010, Google Inc. All rights reserved.

        Redistribution and use in source and binary forms, with or without modification, are permitted provided \
        that the following conditions are met:

          * Redistributions of source code must retain the above copyright notice, this list of conditions and \
        the following disclaimer.

          * Redistributions in binary form must reproduce the above copyright notice, this list of conditions \
        and the following disclaimer in the documentation and/or other materials provided with the distribution.

          * Neither the name of Google nor the names of its contributors may be used to endorse or promote \
        products derived from this software without specific prior written permission.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED \
        WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A \
        PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR \
        ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT \
        LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS \
        INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR \
        TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF \
        ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
        """
}
#endif
