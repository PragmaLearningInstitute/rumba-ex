const JSPDF_ESM_URL = "https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.es.min.js";
const JSPDF_UMD_URL = "https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js";
const DOCX_ESM_URL = "https://cdn.jsdelivr.net/npm/docx@8.5.0/+esm";
const DOCX_UMD_URL = "https://unpkg.com/docx@8.5.0/build/index.js";
const OPENDYSLEXIC_CSS_URL = "https://fonts.cdnfonts.com/css/opendyslexic";

let jsPdfPromise = null;
let docxPromise = null;
const scriptPromises = new Map();

function timestamp() {
  return new Date().toISOString().replace(/\D/g, "").slice(0, 14);
}

function filename(extension) {
  return `rumba-rd-export-${timestamp()}.${extension}`;
}

function downloadBlob(blob, name) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function escapeCssString(value) {
  return String(value).replaceAll("\\", "\\\\").replaceAll('"', '\\"').replace(/[\n\r\f]/g, " ");
}

function primaryFontFamily(style = {}) {
  const raw = String(style.fontFamily || "Arial");
  return raw.split(",")[0].replaceAll('"', "").replaceAll("'", "").trim() || "Arial";
}

function cssFontFamily(style = {}) {
  const primary = primaryFontFamily(style);
  const escaped = escapeCssString(primary);
  const quoted = /\s/.test(escaped) ? `"${escaped}"` : escaped;
  return `${quoted}, Arial, sans-serif`;
}

function normalizedFontSize(style = {}) {
  const value = Number(style.fontSize);
  return Number.isFinite(value) && value > 0 ? value : 13;
}

function isOpenDyslexic(style = {}) {
  return /opendyslexic/i.test(primaryFontFamily(style));
}

function loadScript(src) {
  if (scriptPromises.has(src)) return scriptPromises.get(src);

  const promise = new Promise((resolve, reject) => {
    const existing = Array.from(document.scripts).find((script) => script.dataset.rumbaSrc === src);
    if (existing) {
      if (existing.dataset.rumbaLoaded === "true") {
        resolve();
        return;
      }
      existing.addEventListener("load", resolve, { once: true });
      existing.addEventListener("error", reject, { once: true });
      return;
    }

    const script = document.createElement("script");
    script.src = src;
    script.async = true;
    script.dataset.rumbaSrc = src;
    script.addEventListener("load", () => {
      script.dataset.rumbaLoaded = "true";
      resolve();
    }, { once: true });
    script.addEventListener("error", () => reject(new Error(`Unable to load ${src}`)), { once: true });
    document.head.append(script);
  });

  scriptPromises.set(src, promise);
  return promise;
}

function dependencyError(error) {
  const wrapped = error instanceof Error ? error : new Error(String(error));
  wrapped.isDependencyLoad = true;
  return wrapped;
}

async function loadJsPDF() {
  if (!jsPdfPromise) {
    jsPdfPromise = (async () => {
      try {
        const module = await import(JSPDF_ESM_URL);
        const jsPDF = module.jsPDF || module.default?.jsPDF || module.default;
        if (typeof jsPDF === "function") return jsPDF;
      } catch {}

      try {
        await loadScript(JSPDF_UMD_URL);
        const jsPDF = window.jspdf?.jsPDF || window.jsPDF;
        if (typeof jsPDF === "function") return jsPDF;
      } catch (error) {
        throw dependencyError(error);
      }

      throw dependencyError(new Error("jsPDF is unavailable."));
    })();
  }

  return jsPdfPromise;
}

async function loadDocx() {
  if (!docxPromise) {
    docxPromise = (async () => {
      try {
        const module = await import(DOCX_ESM_URL);
        if (module.Document && module.Packer && module.Paragraph && module.TextRun) return module;
      } catch {}

      try {
        await loadScript(DOCX_UMD_URL);
        const docx = window.docx;
        if (docx?.Document && docx?.Packer && docx?.Paragraph && docx?.TextRun) return docx;
      } catch (error) {
        throw dependencyError(error);
      }

      throw dependencyError(new Error("docx.js is unavailable."));
    })();
  }

  return docxPromise;
}

function handleExportError(error) {
  if (error?.isDependencyLoad) {
    jsPdfPromise = null;
    docxPromise = null;
    alert("Export indisponible momentanément.");
  }
  console.error("RUMBA.RD export failed.", error);
  return false;
}

function parseFormattedHTML(htmlString) {
  const parser = new DOMParser();
  const documentHtml = parser.parseFromString(`<main>${htmlString || ""}</main>`, "text/html");
  const root = documentHtml.body.querySelector("main");
  const segments = [];

  const appendText = (text, bold) => {
    if (!text) return;
    const previous = segments[segments.length - 1];
    if (previous && previous.bold === bold) {
      previous.text += text;
    } else {
      segments.push({ text, bold });
    }
  };

  const walk = (node, bold = false) => {
    if (node.nodeType === Node.TEXT_NODE) {
      appendText(node.nodeValue || "", bold);
      return;
    }

    if (node.nodeType !== Node.ELEMENT_NODE) return;

    const tag = node.tagName.toLowerCase();
    if (tag === "br") {
      appendText("\n", bold);
      return;
    }

    const nextBold = bold || tag === "strong" || tag === "b";
    node.childNodes.forEach((child) => walk(child, nextBold));
  };

  root.childNodes.forEach((child) => walk(child));
  return segments;
}

function textItemsFromSegments(segments) {
  const items = [];
  let currentWord = [];

  const flushWord = () => {
    if (!currentWord.length) return;
    items.push({ type: "word", parts: currentWord });
    currentWord = [];
  };

  segments.forEach((segment) => {
    String(segment.text).split(/(\n|\s+)/g).forEach((part) => {
      if (!part) return;
      if (part === "\n") {
        flushWord();
        items.push({ type: "newline" });
      } else if (/^\s+$/.test(part)) {
        flushWord();
        items.push({ type: "space" });
      } else {
        currentWord.push({ text: part, bold: segment.bold });
      }
    });
  });

  flushWord();
  return items;
}

function docxRunsFromSegments(segments, TextRun, style) {
  const size = normalizedFontSize(style) * 2;
  const font = primaryFontFamily(style);
  const runs = [];

  segments.forEach((segment) => {
    const lines = String(segment.text).split("\n");
    lines.forEach((line, index) => {
      if (index > 0) {
        runs.push(new TextRun({ text: "", break: 1, size, font }));
      }
      if (!line) return;
      runs.push(new TextRun({
        text: line,
        bold: Boolean(segment.bold),
        size,
        font,
      }));
    });
  });

  return runs.length ? runs : [new TextRun({ text: "", size, font })];
}

function setPdfStyle(doc, bold, fontSize) {
  doc.setFont("helvetica", bold ? "bold" : "normal");
  doc.setFontSize(fontSize);
}

function measureWord(doc, parts, fontSize) {
  return parts.reduce((width, part) => {
    setPdfStyle(doc, part.bold, fontSize);
    return width + doc.getTextWidth(part.text);
  }, 0);
}

function drawWord(doc, parts, x, y, fontSize) {
  let cursor = x;
  parts.forEach((part) => {
    setPdfStyle(doc, part.bold, fontSize);
    doc.text(part.text, cursor, y);
    cursor += doc.getTextWidth(part.text);
  });
  return cursor;
}

function renderPdfSegments(doc, segments, style) {
  const fontSize = normalizedFontSize(style);
  const margin = 56.7;
  const pageWidth = doc.internal.pageSize.getWidth();
  const pageHeight = doc.internal.pageSize.getHeight();
  const right = pageWidth - margin;
  const bottom = pageHeight - margin;
  const maxWidth = pageWidth - margin * 2;
  const lineHeight = fontSize * 1.5;
  const spaceWidth = doc.getTextWidth(doc.splitTextToSize(" ", maxWidth)[0] || " ");
  let x = margin;
  let y = margin;
  let pendingSpace = false;

  const nextLine = () => {
    x = margin;
    y += lineHeight;
    pendingSpace = false;
    if (y > bottom) {
      doc.addPage();
      y = margin;
    }
  };

  textItemsFromSegments(segments).forEach((item) => {
    if (item.type === "newline") {
      nextLine();
      return;
    }

    if (item.type === "space") {
      if (x > margin) pendingSpace = true;
      return;
    }

    const wordText = item.parts.map((part) => part.text).join("");
    const splitWord = doc.splitTextToSize(wordText, maxWidth);
    const wordWidth = measureWord(doc, item.parts, fontSize);
    const leadingSpace = pendingSpace ? spaceWidth : 0;

    if (splitWord.length > 1 && wordWidth > maxWidth) {
      splitWord.forEach((piece, index) => {
        if (index > 0 || x > margin) nextLine();
        setPdfStyle(doc, item.parts.some((part) => part.bold), fontSize);
        doc.text(piece, x, y);
        x += doc.getTextWidth(piece);
      });
      pendingSpace = false;
      return;
    }

    if (x + leadingSpace + wordWidth > right && x > margin) {
      nextLine();
    } else if (pendingSpace) {
      x += spaceWidth;
    }

    x = drawWord(doc, item.parts, x, y, fontSize);
    pendingSpace = false;
  });
}

/**
 * Downloads a standalone HTML export preserving the formatted RUMBA.RD markup.
 *
 * @param {string} htmlContent RUMBA-formatted HTML containing optional <strong> nodes.
 * @param {{ fontFamily?: string, fontSize?: number }} style Active reader style.
 * @returns {boolean} true when the download was started.
 */
export function exportAsHTML(htmlContent, style = {}) {
  try {
    const openDyslexicLink = isOpenDyslexic(style)
      ? `<link rel="stylesheet" href="${OPENDYSLEXIC_CSS_URL}">\n`
      : "";
    const documentHtml = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>RUMBA.RD &mdash; Export</title>
${openDyslexicLink}<style>
body { font-family: ${cssFontFamily(style)}; font-size: ${normalizedFontSize(style)}pt; line-height: 1.5; margin: 2cm; color: #171717; }
strong { font-weight: 700; }
</style>
</head>
<body>${htmlContent || ""}</body>
</html>`;
    downloadBlob(new Blob([documentHtml], { type: "text/html;charset=utf-8" }), filename("html"));
    return true;
  } catch (error) {
    return handleExportError(error);
  }
}

/**
 * Downloads a PDF export using jsPDF, preserving bold segments where possible.
 *
 * @param {string} htmlContent RUMBA-formatted HTML containing optional <strong> nodes.
 * @param {{ fontFamily?: string, fontSize?: number }} style Active reader style.
 * @returns {Promise<boolean>} true when the download was started.
 */
export async function exportAsPDF(htmlContent, style = {}) {
  try {
    const jsPDF = await loadJsPDF();
    const doc = new jsPDF({ unit: "pt", format: "a4" });
    renderPdfSegments(doc, parseFormattedHTML(htmlContent), style);
    doc.save(filename("pdf"));
    return true;
  } catch (error) {
    return handleExportError(error);
  }
}

/**
 * Downloads a DOCX export using docx.js, preserving bold runs.
 *
 * @param {string} htmlContent RUMBA-formatted HTML containing optional <strong> nodes.
 * @param {{ fontFamily?: string, fontSize?: number }} style Active reader style.
 * @returns {Promise<boolean>} true when the download was started.
 */
export async function exportAsDOCX(htmlContent, style = {}) {
  try {
    const { Document, Packer, Paragraph, TextRun } = await loadDocx();
    const documentDocx = new Document({
      sections: [{
        children: [
          new Paragraph({
            children: docxRunsFromSegments(parseFormattedHTML(htmlContent), TextRun, style),
          }),
        ],
      }],
    });
    const blob = await Packer.toBlob(documentDocx);
    downloadBlob(blob, filename("docx"));
    return true;
  } catch (error) {
    return handleExportError(error);
  }
}
