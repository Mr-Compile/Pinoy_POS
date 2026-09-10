const fs = require('fs');
const path = 'C:/wamp64/www/Pinoy_Pos/mockups/';

// Stubs for mockup helpers and the browser event used in inline handlers.
function showMenu() {}
function showToast() {}
function closeMenu() {}
const event = { stopPropagation() {}, currentTarget: {}, clientX: 0, clientY: 0 };

['staff_management_screen.html', 'users_screen.html'].forEach(f => {
  const html = fs.readFileSync(path + f, 'utf8');
  const matches = [...html.matchAll(/onclick="([^"]*)"/gs)];
  console.log(f, 'onclick attrs:', matches.length);
  matches.forEach((m, i) => {
    const code = m[1].replace(/&quot;/g, '"').replace(/&apos;/g, "'");
    if (!code.includes('showMenu')) return;
    try {
      eval(code);
      console.log('  menu', i, 'OK');
    } catch(e) {
      console.log('  menu', i, 'ERROR:', e.message);
      console.log('  |', code.slice(0, 200));
    }
  });
});
