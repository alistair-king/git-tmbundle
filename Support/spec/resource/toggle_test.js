const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');

test('commit diffs expand, collapse and reopen without reloading', () => {
  const attributes = {rev: 'abc123', git_path: '/repo', path: 'file.txt'};
  let visible = false;
  let loads = 0;
  let label = '+';
  let html;
  const detail = {
    readAttribute: name => attributes[name] || null,
    setAttribute(name, value) {
      // Match the DOM API: omitting the value throws in WebKit.
      if (arguments.length < 2) throw new TypeError('Missing attribute value');
      attributes[name] = String(value);
    },
    update(value) { html = value; },
    visible: () => visible,
    show() { visible = true; },
    hide() { visible = false; }
  };
  const context = {
    $(id) {
      assert.ok(id === 'detail' || id === 'toggle_link_detail');
      return id === 'detail' ? detail : {update(value) { label = value; }};
    },
    dispatch(params) {
      assert.deepEqual({...params}, {
        controller: 'diff', action: 'diff', revision: 'abc123',
        git_path: '/repo', path: 'file.txt', layout: false
      });
      loads++;
      return '<table>commit changes</table>';
    }
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../../resource/toggle.js'), 'utf8'), context);

  context.toggle_diff('detail');
  assert.equal(visible, true);
  assert.equal(label, '-');
  assert.equal(html, '<table>commit changes</table>');

  context.toggle_diff('detail');
  assert.equal(visible, false);
  assert.equal(label, '+');

  context.toggle_diff('detail');
  assert.equal(visible, true);
  assert.equal(label, '-');
  assert.equal(loads, 1);
});
