import Foundation
import ZIPFoundation

@MainActor
final class DocxExporter {
    func export(
        exercises: [RankedExercise],
        to destinationURL: URL,
        options: ExportOptions
    ) throws {
        let bodyXML = buildDocumentBody(exercises: exercises, options: options)

        let files: [String: Data] = [
            "[Content_Types].xml": Data(contentTypesXML.utf8),
            "_rels/.rels": Data(rootRelsXML.utf8),
            "word/document.xml": Data(bodyXML.utf8),
            "word/styles.xml": Data(stylesXML.utf8),
            "word/_rels/document.xml.rels": Data(documentRelsXML.utf8)
        ]

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let archive = try Archive(url: destinationURL, accessMode: .create)

        for (path, data) in files {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    let startIndex = Int(position)
                    let endIndex = startIndex + size
                    return data.subdata(in: startIndex..<endIndex)
                }
            )
        }
    }

    private func buildDocumentBody(exercises: [RankedExercise], options: ExportOptions) -> String {
        let font = xmlEscape(options.font.wordFontName)
        let baseSizeHalfPoints = options.size * 2
        let smallHintSizeHalfPoints = max(2, (options.size - 2) * 2)

        var paragraphs: [String] = []
        paragraphs.append(paragraph("Exercices personnalises Rumba", font: font, sizeHalfPoints: baseSizeHalfPoints + 6, bold: true))

        for (index, ranked) in exercises.enumerated() {
            let number = index + 1
            paragraphs.append(paragraph("Exercice \(number): \(ranked.exercise.title)", font: font, sizeHalfPoints: baseSizeHalfPoints + 2, bold: true))
            paragraphs.append(paragraph(ranked.exercise.content, font: font, sizeHalfPoints: baseSizeHalfPoints))
            let hint = ranked.exercise.hint ?? "Aucun indice"
            let upsideDownHint = upsideDown("Indice: \(hint)")
            paragraphs.append(paragraph(upsideDownHint, font: font, sizeHalfPoints: smallHintSizeHalfPoints))
            paragraphs.append(paragraph("", font: font, sizeHalfPoints: baseSizeHalfPoints))
        }

        paragraphs.append(pageBreak())
        paragraphs.append(paragraph("page de reponse", font: font, sizeHalfPoints: baseSizeHalfPoints + 4, bold: true))

        for (index, ranked) in exercises.enumerated() {
            let number = index + 1
            let answer = "\(number). \(ranked.exercise.correctAnswer)"
            paragraphs.append(paragraph(answer, font: font, sizeHalfPoints: baseSizeHalfPoints))
        }

        paragraphs.append(paragraph("", font: font, sizeHalfPoints: baseSizeHalfPoints))
        paragraphs.append(paragraph("Indices", font: font, sizeHalfPoints: smallHintSizeHalfPoints, bold: true))

        for (index, ranked) in exercises.enumerated() {
            let number = index + 1
            let hint = ranked.exercise.hint ?? "Aucun indice"
            let upsideDownHint = upsideDown("Indice: \(hint)")
            paragraphs.append(paragraph("\(number). \(upsideDownHint)", font: font, sizeHalfPoints: smallHintSizeHalfPoints))
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(paragraphs.joined(separator: "\n"))
            <w:sectPr>
              <w:pgSz w:w="11906" w:h="16838"/>
              <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private func paragraph(_ text: String, font: String, sizeHalfPoints: Int, bold: Bool = false) -> String {
        let escaped = xmlEscape(text)
        let boldTag = bold ? "<w:b/>" : ""

        return """
        <w:p>
          <w:pPr>
            <w:spacing w:line="360" w:lineRule="auto"/>
          </w:pPr>
          <w:r>
            <w:rPr>
              \(boldTag)
              <w:rFonts w:ascii="\(font)" w:hAnsi="\(font)" w:cs="\(font)"/>
              <w:sz w:val="\(sizeHalfPoints)"/>
              <w:szCs w:val="\(sizeHalfPoints)"/>
            </w:rPr>
            <w:t xml:space="preserve">\(escaped)</w:t>
          </w:r>
        </w:p>
        """
    }

    private func pageBreak() -> String {
        """
        <w:p>
          <w:r>
            <w:br w:type="page"/>
          </w:r>
        </w:p>
        """
    }

    private func xmlEscape(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func upsideDown(_ text: String) -> String {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()

        let map: [Character: String] = [
            "a": "ɐ", "b": "q", "c": "ɔ", "d": "p", "e": "ǝ", "f": "ɟ", "g": "ƃ", "h": "ɥ",
            "i": "ᴉ", "j": "ɾ", "k": "ʞ", "l": "l", "m": "ɯ", "n": "u", "o": "o", "p": "d",
            "q": "b", "r": "ɹ", "s": "s", "t": "ʇ", "u": "n", "v": "ʌ", "w": "ʍ", "x": "x",
            "y": "ʎ", "z": "z",
            "0": "0", "1": "Ɩ", "2": "ᄅ", "3": "Ɛ", "4": "ㄣ", "5": "ϛ", "6": "9", "7": "ㄥ", "8": "8", "9": "6",
            ".": "˙", ",": "'", "'": ",", "\"": "„", "!": "¡", "?": "¿",
            "(": ")", ")": "(", "[": "]", "]": "[", "{": "}", "}": "{",
            ":": "ː", ";": "؛", "<": ">", ">": "<", "&": "⅋", "_": "‾",
            " ": " "
        ]

        return normalized.reversed().map { map[$0] ?? String($0) }.joined()
    }

    private let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    </Types>
    """

    private let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    private let documentRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>
    """

    private let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
        <w:name w:val="Normal"/>
      </w:style>
    </w:styles>
    """
}
