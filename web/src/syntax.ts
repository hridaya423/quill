import type { BlockContext, InlineContext, Line, MarkdownConfig } from '@lezer/markdown';
import { tags } from '@lezer/highlight';

const HighlightDelim = { resolve: 'Highlight', mark: 'HighlightMark' };
const Punctuation = /[!-\/:-@\[-`{-~¡‐-‧]/;

function closing(cx: InlineContext, from: number) {
  for (let pos = from; pos < cx.end - 1; pos++) {
    const c = cx.char(pos);
    if (c === 10) return -1;
    if (c === 93 && cx.char(pos + 1) === 93) return pos;
  }
  return -1;
}

function link(cx: InlineContext, pos: number, embed: boolean) {
  const open = pos + (embed ? 3 : 2);
  const close = closing(cx, open);
  if (close < 0 || close === open) return -1;
  const children = [cx.elt('WikiMark', pos, open)];
  let pipe = -1;
  for (let p = open; p < close; p++) {
    if (cx.char(p) === 124) {
      pipe = cx.char(p - 1) === 92 ? p - 1 : p;
      break;
    }
  }
  const targetEnd = pipe < 0 ? close : pipe;
  if (targetEnd > open) children.push(cx.elt('WikiTarget', open, targetEnd));
  if (pipe >= 0) {
    const aliasFrom = cx.char(pipe) === 92 ? pipe + 2 : pipe + 1;
    children.push(cx.elt('WikiPipe', pipe, aliasFrom));
    if (close > aliasFrom) children.push(cx.elt('WikiAlias', aliasFrom, close));
  }
  children.push(cx.elt('WikiMark', close, close + 2));
  return cx.addElement(cx.elt(embed ? 'Embed' : 'WikiLink', pos, close + 2, children));
}

const tagChar = /[\p{L}\p{N}_\-\/]/u;

function isCommentLine(line: Line) {
  return line.text.slice(line.pos, line.pos + 2) === '%%';
}

export const obsidian: MarkdownConfig = {
  defineNodes: [
    { name: 'WikiLink' },
    { name: 'Embed' },
    { name: 'WikiMark', style: tags.processingInstruction },
    { name: 'WikiTarget' },
    { name: 'WikiPipe', style: tags.processingInstruction },
    { name: 'WikiAlias' },
    { name: 'Highlight' },
    { name: 'HighlightMark', style: tags.processingInstruction },
    { name: 'Comment', style: tags.comment },
    { name: 'CommentBlock', block: true, style: tags.comment },
    { name: 'CommentMark', style: tags.processingInstruction },
    { name: 'BlockId', style: tags.processingInstruction },
    { name: 'FootnoteRef' },
    { name: 'Tag' },
    { name: 'CalloutMark' },
  ],
  parseBlock: [
    {
      name: 'CommentBlock',
      before: 'HTMLBlock',
      parse(cx: BlockContext, line: Line) {
        if (!isCommentLine(line)) return false;
        const rest = line.text.slice(line.pos + 2);
        if (rest.includes('%%')) {
          if (!/%%\s*$/.test(rest)) return false;
          const from = cx.lineStart + line.pos;
          cx.addElement(cx.elt('CommentBlock', from, cx.lineStart + line.text.length));
          cx.nextLine();
          return true;
        }
        const from = cx.lineStart + line.pos;
        while (cx.nextLine()) {
          const at = line.text.indexOf('%%');
          if (at >= 0) {
            const to = cx.lineStart + line.text.length;
            cx.nextLine();
            cx.addElement(cx.elt('CommentBlock', from, to));
            return true;
          }
        }
        cx.addElement(cx.elt('CommentBlock', from, cx.prevLineEnd()));
        return true;
      },
    },
  ],
  parseInline: [
    {
      name: 'Embed',
      parse(cx, next, pos) {
        if (next !== 33 || cx.char(pos + 1) !== 91 || cx.char(pos + 2) !== 91) return -1;
        return link(cx, pos, true);
      },
      before: 'Image',
    },
    {
      name: 'WikiLink',
      parse(cx, next, pos) {
        if (next !== 91 || cx.char(pos + 1) !== 91) return -1;
        return link(cx, pos, false);
      },
      before: 'Link',
    },
    {
      name: 'CalloutMark',
      parse(cx, next, pos) {
        if (next !== 91 || cx.char(pos + 1) !== 33 || pos !== cx.offset) return -1;
        let p = pos + 2;
        while (p < cx.end && /[\w-]/.test(String.fromCharCode(cx.char(p)))) p++;
        if (p === pos + 2 || cx.char(p) !== 93) return -1;
        p++;
        if (cx.char(p) === 43 || cx.char(p) === 45) p++;
        return cx.addElement(cx.elt('CalloutMark', pos, p));
      },
      before: 'Link',
    },
    {
      name: 'FootnoteRef',
      parse(cx, next, pos) {
        if (next !== 91 || cx.char(pos + 1) !== 94) return -1;
        let p = pos + 2;
        while (p < cx.end && cx.char(p) !== 93 && cx.char(p) !== 10 && cx.char(p) !== 32) p++;
        if (p === pos + 2 || cx.char(p) !== 93) return -1;
        return cx.addElement(cx.elt('FootnoteRef', pos, p + 1));
      },
      before: 'Link',
    },
    {
      name: 'Highlight',
      parse(cx, next, pos) {
        if (next !== 61 || cx.char(pos + 1) !== 61 || cx.char(pos + 2) === 61) return -1;
        const before = cx.slice(pos - 1, pos), after = cx.slice(pos + 2, pos + 3);
        const sBefore = /\s|^$/.test(before), sAfter = /\s|^$/.test(after);
        const pBefore = Punctuation.test(before), pAfter = Punctuation.test(after);
        return cx.addDelimiter(HighlightDelim, pos, pos + 2, !sAfter && (!pAfter || sBefore || pBefore), !sBefore && (!pBefore || sAfter || pAfter));
      },
      after: 'Emphasis',
    },
    {
      name: 'Comment',
      parse(cx, next, pos) {
        if (next !== 37 || cx.char(pos + 1) !== 37) return -1;
        for (let p = pos + 2; p < cx.end - 1; p++) {
          if (cx.char(p) === 37 && cx.char(p + 1) === 37) {
            return cx.addElement(cx.elt('Comment', pos, p + 2, [cx.elt('CommentMark', pos, pos + 2), cx.elt('CommentMark', p, p + 2)]));
          }
        }
        return -1;
      },
      before: 'Emphasis',
    },
    {
      name: 'BlockId',
      parse(cx, next, pos) {
        if (next !== 94 || (pos > cx.offset && cx.char(pos - 1) !== 32)) return -1;
        let p = pos + 1;
        while (p < cx.end && /[A-Za-z0-9-]/.test(String.fromCharCode(cx.char(p)))) p++;
        if (p === pos + 1 || (p < cx.end && cx.char(p) !== 10)) return -1;
        return cx.addElement(cx.elt('BlockId', pos > cx.offset ? pos - 1 : pos, p));
      },
    },
    {
      name: 'Tag',
      parse(cx, next, pos) {
        if (next !== 35 || (pos > cx.offset && !/\s/.test(cx.slice(pos - 1, pos)))) return -1;
        let p = pos + 1;
        let word = false;
        while (p < cx.end && tagChar.test(cx.slice(p, p + 1))) {
          if (!/\d/.test(cx.slice(p, p + 1))) word = true;
          p++;
        }
        if (!word) return -1;
        return cx.addElement(cx.elt('Tag', pos, p));
      },
    },
  ],
};
