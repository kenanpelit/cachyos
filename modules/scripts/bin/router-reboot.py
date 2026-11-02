#!/usr/bin/env python3
"""router-reboot: restart the home router (Residential Gateway at 192.168.0.1) the way its web page's Reboot button does.

Logs in as admin with the password from `pass show router-pass`, opens Status > Security (RgSecurity.asp) and sends its form as
the browser would (every field as the page has it, only the checked radio buttons) with ResetModem=1. It refuses to send if the
page would change anything else: a password field with something in it, or "Restore Factory Defaults" set to Yes.

    router-reboot            restart it (asks first)
    router-reboot -y         restart without asking
    router-reboot --dry-run  log in and show what would be sent, send nothing
"""
import html.parser
import http.cookiejar
import re
import subprocess
import sys
import urllib.parse
import urllib.request

HOST = 'http://192.168.0.1'
USER = 'admin'
PASS_ENTRY = 'router-pass'


class Form(html.parser.HTMLParser):
    """The fields of one form, as a browser submits them."""

    def __init__(self, name):
        super().__init__()
        self.name, self.inside, self.action, self.fields = name, False, None, []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'form':
            self.inside = a.get('name') == self.name
            if self.inside:
                self.action = a.get('action')
        elif tag == 'input' and self.inside and a.get('name'):
            kind = (a.get('type') or 'text').lower()
            if kind in ('button', 'submit', 'reset', 'image'):
                return
            if kind in ('radio', 'checkbox') and 'checked' not in a:
                return
            self.fields.append((a['name'], (a.get('value') or '').replace('\x00', '')))

    def handle_endtag(self, tag):
        if tag == 'form':
            self.inside = False


def main():
    dry = '--dry-run' in sys.argv
    sure = '-y' in sys.argv or '--yes' in sys.argv
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    get = lambda path: opener.open(HOST + path, timeout=10).read().decode('windows-1254', 'replace')

    login = get('/')
    m = re.search(r'name="loginid" value=([0-9a-f]+)', login)
    landed = ''
    if m:  # the router keeps a session per computer: no login form when this one is still logged in
        password = subprocess.run(['pass', 'show', PASS_ENTRY], capture_output=True, text=True)
        if password.returncode:
            sys.exit(f'router-reboot: pass show {PASS_ENTRY} failed: {password.stderr.strip()}')
        data = urllib.parse.urlencode({'loginid': m.group(1), 'loginUsername': USER,
                                       'loginPassword': password.stdout.split('\n', 1)[0], 'LoginUserApply': '1'}).encode()
        landed = opener.open(HOST + '/goform/login', data, timeout=10).geturl()
    page = get('/RgSecurity.asp')
    if 'login.asp' in landed or '<title>Residential Gateway Login' in page:
        sys.exit('router-reboot: the router did not accept the login')

    form = Form('Security')
    form.feed(page)
    fields = dict(form.fields)
    if form.action != '/goform/RgSecurity' or 'ResetModem' not in fields or 'RgSecurityId' not in fields:
        sys.exit('router-reboot: the Security page is not what this script knows; nothing sent')
    if any(fields.get(k) for k in ('Password', 'PasswordReEnter', 'OldPassword')) or 'RestoreFactoryYes' in fields:
        sys.exit('router-reboot: the form would change the password or restore factory defaults; nothing sent')
    fields['ResetModem'] = '1'

    if dry:
        shown = {k: ('(empty)' if v == '' else v) for k, v in fields.items() if k != 'RgSecurityId'}
        print('logged in; would send to /goform/RgSecurity:', shown)
        return
    if not sure and input('Restart the router now? The internet goes for about two minutes. [y/N] ').strip().lower() not in ('y', 'e', 'yes', 'evet'):
        print('not restarted')
        return
    try:
        opener.open(HOST + form.action, urllib.parse.urlencode(list(fields.items())).encode(), timeout=10).read()
    except OSError:
        pass  # it often goes down before it answers
    print('restart sent; the router is back in about two minutes')


if __name__ == '__main__':
    main()
