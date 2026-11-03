export const patches = [
  [
    "const buildDecorations$1 = (state) => {\n\tconst decorations = [];",
    "const buildDecorations$1 = (state, from = 0, to = state.doc.length, decorations = []) => {",
  ],
  [
    "\tsyntaxTree(state).iterate({ enter: (node) => {\n\t\tconst selectionTouchesNodeRange = state.selection.ranges.some",
    "\tsyntaxTree(state).iterate({ from, to, enter: (node) => {\n\t\tif (__outside(node, from, to)) return node.from <= from && node.to >= to ? void 0 : false;\n\t\tconst selectionTouchesNodeRange = state.selection.ranges.some",
  ],
  [
    "\t\tif (tr.docChanged || tr.selection || syntaxTree(tr.startState) !== syntaxTree(tr.state)) return buildDecorations$1(tr.state);\n\t\treturn deco.map(tr.changes);",
    "\t\treturn __incremental(deco, tr, buildDecorations$1);",
  ],
  [
    "const buildDecorations = (state) => {\n\tconst decorations = [];",
    "const buildDecorations = (state, from = 0, to = state.doc.length, decorations = []) => {",
  ],
  [
    "\tsyntaxTree(state).iterate({ enter: (node) => {\n\t\tif (rangeInsideLanguageFold(state, node.from, node.to)) return false;",
    "\tsyntaxTree(state).iterate({ from, to, enter: (node) => {\n\t\tif (__outside(node, from, to)) return node.from <= from && node.to >= to ? void 0 : false;\n\t\tif (rangeInsideLanguageFold(state, node.from, node.to)) return false;",
  ],
  [
    "\t\tif (tr.docChanged || tr.selection || syntaxTree(tr.startState) !== syntaxTree(tr.state) || tr.startState.field(foldState, false) !== tr.state.field(foldState, false)) return buildDecorations(tr.state);\n\t\treturn deco.map(tr.changes);",
    "\t\tif (tr.startState.field(foldState, false) !== tr.state.field(foldState, false)) return buildDecorations(tr.state);\n\t\treturn __incremental(deco, tr, buildDecorations);",
  ],
  [
    "\tsyntaxTree(view.state).iterate({ enter(node) {\n\t\tif (node.type.name != \"Blockquote\") return;",
    "\tsyntaxTree(view.state).iterate({ from: view.viewport.from, to: view.viewport.to, enter(node) {\n\t\tif (node.type.name != \"Blockquote\") return;",
  ],
  [
    "const revealTargetAtWidgetBoundary = (state, direction) => {\n\tconst decorations = state.field(foldExtension);\n\tconst cursorAt = state.selection.main.head;\n\tfor (let iter = decorations.iter(); iter.value; iter.next()) {\n\t\tif (!decorationHasReplaceWidget(iter.value)) continue;\n\t\tif (direction === \"down\" && cursorAt == iter.from - 1) return iter.from;\n\t\tif (direction === \"up\" && cursorAt == iter.to + 1) return iter.to;\n\t}\n\treturn null;\n};",
    "const revealTargetAtWidgetBoundary = (state, direction) => {\n\tconst decorations = state.field(foldExtension);\n\tconst cursorAt = state.selection.main.head;\n\tconst at = direction === \"down\" ? cursorAt + 1 : cursorAt - 1;\n\tlet found = null;\n\tif (at < 0 || at > state.doc.length) return null;\n\tdecorations.between(at, at, (from, to, value) => {\n\t\tif (!decorationHasReplaceWidget(value)) return;\n\t\tif (direction === \"down\" && cursorAt == from - 1) { found = from; return false; }\n\t\tif (direction === \"up\" && cursorAt == to + 1) { found = to; return false; }\n\t});\n\treturn found;\n};",
  ],
  [
    "const revealTargetOnAdjacentLine = (state, direction) => {\n\tconst decorations = state.field(foldExtension);\n\tconst cursorAt = state.selection.main.head;\n\tconst line = state.doc.lineAt(cursorAt);\n\tconst docText = state.doc;\n\tlet candidate = null;\n\tfor (let iter = decorations.iter(); iter.value; iter.next()) {\n\t\tif (!decorationHasReplaceWidget(iter.value)) continue;\n\t\tif (iter.value.spec.proseMarkSkipAdjacentArrowReveal) continue;\n\t\tif (direction === \"up\" && iter.to < line.from && /^[\\t \\n\\r]+$/.test(docText.sliceString(iter.to, line.from))) {\n\t\t\tcandidate = candidate == null || iter.to > candidate ? iter.to : candidate;\n\t\t\tcontinue;\n\t\t}\n\t\tif (direction === \"down\" && iter.from > line.to && /^[\\t \\n\\r]+$/.test(docText.sliceString(line.to, iter.from))) candidate = candidate == null || iter.from < candidate ? iter.from : candidate;\n\t}\n\treturn candidate;\n};",
    "const revealTargetOnAdjacentLine = (state, direction) => {\n\tconst decorations = state.field(foldExtension);\n\tconst cursorAt = state.selection.main.head;\n\tconst line = state.doc.lineAt(cursorAt);\n\tconst docText = state.doc;\n\tconst blank = (pos) => /[\\t \\n\\r]/.test(docText.sliceString(pos, pos + 1));\n\tlet candidate = null;\n\tlet from = line.to + 1, to = line.from - 1;\n\tif (direction === \"down\") { to = line.to; while (to < docText.length && blank(to)) to++; }\n\telse { from = line.from; while (from > 0 && blank(from - 1)) from--; }\n\tif (from > to) return null;\n\tdecorations.between(from, to, (decoFrom, decoTo, value) => {\n\t\tif (!decorationHasReplaceWidget(value)) return;\n\t\tif (value.spec.proseMarkSkipAdjacentArrowReveal) return;\n\t\tif (direction === \"up\" && decoTo < line.from && /^[\\t \\n\\r]+$/.test(docText.sliceString(decoTo, line.from))) {\n\t\t\tcandidate = candidate == null || decoTo > candidate ? decoTo : candidate;\n\t\t\treturn;\n\t\t}\n\t\tif (direction === \"down\" && decoFrom > line.to && /^[\\t \\n\\r]+$/.test(docText.sliceString(line.to, decoFrom))) candidate = candidate == null || decoFrom < candidate ? decoFrom : candidate;\n\t});\n\treturn candidate;\n};",
  ],
  [
    "const widgetForRevealTarget = (state, direction, target) => {\n\tconst decorations = state.field(foldExtension);\n\tfor (let iter = decorations.iter(); iter.value; iter.next()) {\n\t\tif (!decorationHasReplaceWidget(iter.value)) continue;\n\t\tif (direction === \"down\" && iter.from === target) return {\n\t\t\tfrom: iter.from,\n\t\t\tto: iter.to\n\t\t};\n\t\tif (direction === \"up\" && iter.to === target) return {\n\t\t\tfrom: iter.from,\n\t\t\tto: iter.to\n\t\t};\n\t}\n\treturn null;\n};",
    "const widgetForRevealTarget = (state, direction, target) => {\n\tconst decorations = state.field(foldExtension);\n\tlet found = null;\n\tdecorations.between(target, target, (from, to, value) => {\n\t\tif (!decorationHasReplaceWidget(value)) return;\n\t\tif (direction === \"down\" && from === target || direction === \"up\" && to === target) { found = { from, to }; return false; }\n\t});\n\treturn found;\n};",
  ],
  [
    "\tupdate(u) {\n\t\tif (u.docChanged) this.decorations = this.decorations.map(u.changes);\n\t\tif (u.docChanged || u.viewportChanged || u.selectionSet) this.requestMeasure(u.view, 0);\n\t\tconst refreshCount = u.transactions.find((tr) => tr.annotation(softIndentRefresh) !== void 0)?.annotation(softIndentRefresh);\n\t\tif (refreshCount !== void 0) this.requestMeasure(u.view, refreshCount);\n\t}\n",
    "\tupdate(u) {\n\t\tif (u.docChanged) {\n\t\t\tthis.decorations = this.decorations.map(u.changes);\n\t\t\tconst kept = new Map();\n\t\t\tfor (const [from, entry] of this.widths) {\n\t\t\t\tlet touched = false;\n\t\t\t\tu.changes.iterChangedRanges((fromA, toA) => { if (fromA <= from + entry.text.length && toA >= from) touched = true; });\n\t\t\t\tif (!touched) kept.set(u.changes.mapPos(from), entry);\n\t\t\t}\n\t\t\tthis.widths = kept;\n\t\t}\n\t\tif (u.docChanged || u.viewportChanged || u.selectionSet || u.geometryChanged) this.requestMeasure(u.view, 0);\n\t\tconst refreshCount = u.transactions.find((tr) => tr.annotation(softIndentRefresh) !== void 0)?.annotation(softIndentRefresh);\n\t\tif (refreshCount !== void 0) this.requestMeasure(u.view, refreshCount);\n\t}\n",
  ],
  [
    "\tmeasureIndents(view) {\n\t\tconst indents = [];\n\t\tfor (const { from, to } of view.visibleRanges) {\n\t\t\tconst start = view.state.doc.lineAt(from);\n\t\t\tconst end = view.state.doc.lineAt(to);\n\t\t\tfor (let i = start.number; i <= end.number; i++) {\n\t\t\t\tconst line = view.state.doc.line(i);\n\t\t\t\tconst nonContent = matchSoftIndentPrefix(view.state.sliceDoc(line.from, line.to));\n\t\t\t\tif (!nonContent) continue;\n\t\t\t\tconst indentWidth = measureSoftIndentWidth(view, softIndentPrefixBounds(line.from, nonContent));\n\t\t\t\tif (!indentWidth) continue;\n\t\t\t\tindents.push({\n\t\t\t\t\tlineNumber: i,\n\t\t\t\t\tindentWidth\n\t\t\t\t});\n\t\t\t}\n\t\t}\n\t\treturn indents;\n\t}",
    "\twidths = /* @__PURE__ */ new Map();\n\tfont = \"\";\n\tmeasureIndents(view) {\n\t\tconst indents = [];\n\t\tconst style = getComputedStyle(view.contentDOM);\n\t\tconst font = style.fontFamily + style.fontSize;\n\t\tif (font !== this.font) { this.font = font; this.widths.clear(); }\n\t\tconst ranges = view.state.selection.ranges;\n\t\tfor (const { from, to } of view.visibleRanges) {\n\t\t\tconst start = view.state.doc.lineAt(from);\n\t\t\tconst end = view.state.doc.lineAt(to);\n\t\t\tfor (let i = start.number; i <= end.number; i++) {\n\t\t\t\tconst line = view.state.doc.line(i);\n\t\t\t\tconst text = view.state.sliceDoc(line.from, line.to);\n\t\t\t\tconst nonContent = matchSoftIndentPrefix(text);\n\t\t\t\tconst lineEl = nonContent ? lineElementAt(view, line.from) : null;\n\t\t\t\tif (!lineEl || view.posAtDOM(lineEl, 0) !== line.from) continue;\n\t\t\t\tconst selected = ranges.some((r) => r.from <= line.to && r.to >= line.from);\n\t\t\t\tconst known = this.widths.get(line.from);\n\t\t\t\tlet indentWidth;\n\t\t\t\tif (known && known.text === text && known.selected === selected && known.width > 0) indentWidth = known.width;\n\t\t\t\telse {\n\t\t\t\t\tindentWidth = Math.round(measureSoftIndentWidth(view, softIndentPrefixBounds(line.from, nonContent)));\n\t\t\t\t\tthis.widths.set(line.from, { text, selected, width: indentWidth });\n\t\t\t\t}\n\t\t\t\tif (!indentWidth) continue;\n\t\t\t\tindents.push({\n\t\t\t\t\tlineNumber: i,\n\t\t\t\t\tindentWidth\n\t\t\t\t});\n\t\t\t}\n\t\t}\n\t\tif (this.widths.size > 4000) this.widths.clear();\n\t\treturn indents;\n\t}",
  ],
  [
    "\t\telse {\n\t\t\tconst roundNumber = String(refreshCount);\n\t\t\tconsole.warn(`Soft indent: indents still changing after ${roundNumber} refresh rounds. Affected lines:`, changedLines);\n\t\t}",
    "\t\telse {\n\t\t\tconst unstable = changedLines.filter((line) => line.oldStyle !== void 0 && line.newStyle !== void 0);\n\t\t\tif (unstable.length) console.warn(`Soft indent: indents still changing after ${String(refreshCount)} refresh rounds. Affected lines:`, unstable);\n\t\t}",
  ],
  [
    "\treturn lineEl.getBoundingClientRect().left + SOFT_INDENT_BASE_PADDING;",
    "\tconst style = getComputedStyle(lineEl);\n\treturn lineEl.getBoundingClientRect().left + parseFloat(style.paddingLeft) + parseFloat(style.textIndent);",
  ],
  [
    "px`}; text-indent: -${indentWidth.toString()}px;`;",
    "px`}; text-indent: -${indentWidth.toString()}px; --hang: ${indentWidth.toString()}px;`;",
  ],
];
