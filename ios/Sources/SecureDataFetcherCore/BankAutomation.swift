import Foundation

public struct StatementRequest: Equatable, Sendable {
    public let requestId: String
    public let month: Int
    public let year: Int

    public init(requestId: String, month: Int, year: Int) {
        self.requestId = requestId
        self.month = month
        self.year = year
    }
}

public protocol BankScript {
    var bankId: String { get }
    var loginURL: URL { get }

    func injectCredentials(username: String, password: String) -> String
    func detectLoginSuccess() -> String
    func detectTwoFactorPrompt() -> String
    func detectManualChallengeDescriptor() -> String
    func navigateToStatements() -> String
    func selectStatement(month: Int, year: Int) -> String
    func triggerDownload() -> String
    func debugStatementSelectionSnapshot(month: Int, year: Int) -> String
    func debugDownloadSnapshot() -> String
}

public extension BankScript {
    func debugStatementSelectionSnapshot(month: Int, year: Int) -> String {
        "(() => '')();"
    }

    func debugDownloadSnapshot() -> String {
        "(() => '')();"
    }
}

public struct ChaseBankScript: BankScript {
    public let bankId: String = "default"
    public let loginURL: URL

    public init(loginURL: URL = URL(string: "https://www.chase.com/")!) {
        self.loginURL = loginURL
    }

    public func injectCredentials(username: String, password: String) -> String {
        let safeUsername = jsStringLiteral(username)
        let safePassword = jsStringLiteral(password)

        return """
        (() => {
          const user = document.querySelector(
            'input[name="userId"], input[name="userID"], input#userId, input#userID, input[autocomplete="username"]'
          );
          const pass = document.querySelector(
            'input[name="password"], input#password, input[type="password"], input[autocomplete="current-password"]'
          );
          if (!user || !pass) return false;

          const applyValue = (input, value) => {
            input.focus();
            input.value = value;
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
          };

          applyValue(user, \(safeUsername));
          applyValue(pass, \(safePassword));

          const form = user.closest('form') || pass.closest('form');
          if (form) {
            form.submit();
            return true;
          }

          const submit = document.querySelector(
            'button[type="submit"], input[type="submit"], button[id*="signin"], button[class*="signin"]'
          );
          if (!submit) return false;

          submit.click();
          return true;
        })();
        """
    }

    public func detectLoginSuccess() -> String {
        """
        (() => {
          const host = (location.hostname || '').toLowerCase();
          const href = (location.href || '').toLowerCase();
          if (!host.endsWith('chase.com')) return false;

          return href.includes('/web/auth/dashboard') ||
                 href.includes('#/dashboard') ||
                 href.includes('/dashboard/documents') ||
                 href.includes('mode=documents');
        })();
        """
    }

    public func detectTwoFactorPrompt() -> String {
        """
        (() => {
          const text = (document.body?.innerText || '')
            .toLowerCase()
            .replace(/\\s+/g, ' ');

          const hasCodeInput = Array.from(document.querySelectorAll('input, textarea')).some((el) => {
            const id = (el.id || '').toLowerCase();
            const name = (el.name || '').toLowerCase();
            const auto = (el.autocomplete || '').toLowerCase();
            const placeholder = (el.placeholder || '').toLowerCase();
            return auto === 'one-time-code' ||
                   id.includes('otp') ||
                   name.includes('otp') ||
                   id.includes('verification') ||
                   name.includes('verification') ||
                   id.includes('security') ||
                   name.includes('security') ||
                   (id.includes('code') && !id.includes('zipcode')) ||
                   (name.includes('code') && !name.includes('zipcode')) ||
                   placeholder.includes('code');
          });

          const hasCaptcha = Boolean(
            document.querySelector('iframe[src*="recaptcha"], iframe[title*="captcha"], div.g-recaptcha, [data-sitekey]')
          );

          return hasCodeInput ||
                 hasCaptcha ||
                 text.includes('verification code') ||
                 text.includes('two-step') ||
                 text.includes('two factor') ||
                 text.includes('one-time code') ||
                 text.includes('security code') ||
                 text.includes('text you a code') ||
                 text.includes('authenticator app') ||
                 text.includes('security question') ||
                 text.includes('captcha') ||
                 text.includes('i am not a robot');
        })();
        """
    }

    public func detectManualChallengeDescriptor() -> String {
        """
        (() => {
          const text = (document.body?.innerText || '').toLowerCase().replace(/\\s+/g, ' ');
          const hasCaptcha = Boolean(
            document.querySelector('iframe[src*="recaptcha"], iframe[title*="captcha"], div.g-recaptcha, [data-sitekey]')
          );

          const hasAuthenticatorSignal = text.includes('authenticator app') ||
            text.includes('authenticator') ||
            text.includes('auth app');

          const hasSMSignal = text.includes('text you a code') ||
            text.includes('text message') ||
            text.includes('sms');

          const hasSecurityQuestionSignal = text.includes('security question') ||
            text.includes('answer this question');

          const hasCodeSignal = text.includes('verification code') ||
            text.includes('one-time code') ||
            text.includes('security code') ||
            text.includes('enter code');

          let kind = 'unknown';
          let prompt = 'Complete verification in the browser, then continue.';

          if (hasCaptcha || text.includes('captcha') || text.includes('i am not a robot')) {
            kind = 'captcha';
            prompt = 'Complete the captcha challenge, then tap Continue.';
          } else if (hasSecurityQuestionSignal) {
            kind = 'security_question';
            prompt = 'Answer the security question, then tap Continue.';
          } else if (hasAuthenticatorSignal) {
            kind = 'authenticator_app';
            prompt = 'Enter code from your authenticator app, then tap Continue.';
          } else if (hasSMSignal) {
            kind = 'sms_code';
            prompt = 'Enter the SMS code from your bank, then tap Continue.';
          } else if (hasCodeSignal) {
            kind = 'verification_code';
            prompt = 'Enter the verification code, then tap Continue.';
          }

          return JSON.stringify({ kind, prompt });
        })();
        """
    }

    public func navigateToStatements() -> String {
        """
        (() => {
          const target = 'https://secure.chase.com/web/auth/dashboard#/dashboard/documents/myDocs/index;mode=documents';
          if ((location.href || '').includes('/dashboard/documents')) {
            return true;
          }

          location.href = target;
          return true;
        })();
        """
    }

    public func selectStatement(month: Int, year: Int) -> String {
        """
        (() => {
          const months = [
            'january', 'february', 'march', 'april', 'may', 'june',
            'july', 'august', 'september', 'october', 'november', 'december'
          ];
          const monthIndex = Math.max(0, Math.min(11, \(month) - 1));
          const year = String(\(year));
          const monthFull = months[monthIndex];
          const monthShort = monthFull.slice(0, 3);
          const monthNumber = String(monthIndex + 1);
          const monthPadded = monthNumber.padStart(2, '0');

          const normalize = (value) => String(value || '')
            .toLowerCase()
            .replace(/\\s+/g, ' ')
            .trim();

          const textFor = (el) => normalize([
            el.innerText,
            el.textContent,
            el.getAttribute?.('aria-label'),
            el.getAttribute?.('title'),
            el.getAttribute?.('data-testid'),
            el.getAttribute?.('data-label'),
            el.getAttribute?.('href'),
            el.value
          ].filter(Boolean).join(' '));

          const click = (el) => {
            if (!el) return false;
            if (el.disabled === true) return false;
            try {
              el.scrollIntoView({ block: 'center', inline: 'nearest' });
            } catch (_) {}
            el.click();
            return true;
          };

          const clickTarget = (el) => {
            if (!el) return false;

            if (el.matches?.('a, button, [role="button"], input[type="button"], input[type="submit"]')) {
              return click(el);
            }

            const nested = el.querySelector?.('a, button, [role="button"], input[type="button"], input[type="submit"]');
            return click(nested);
          };

          const candidates = Array.from(document.querySelectorAll(
            'a, button, [role="button"], input[type="button"], input[type="submit"], tr, li, article, div[role="row"], div[data-testid]'
          ));

          let best = null;
          let bestScore = -1;

          for (const el of candidates) {
            const text = textFor(el);
            if (!text) continue;

            let score = 0;
            if (text.includes(year)) score += 2;
            if (text.includes(monthFull) || text.includes(monthShort)) score += 4;
            if (text.includes(`${monthNumber}/${year}`) || text.includes(`${monthPadded}/${year}`) || text.includes(`${year}-${monthPadded}`)) {
              score += 4;
            }
            if (text.includes('statement') || text.includes('document')) score += 2;
            if (text.includes('pdf') || text.includes('download') || text.includes('view')) score += 2;
            if (text.includes('credit card') || text.includes('checking') || text.includes('savings') || text.includes('business')) {
              score += 1;
            }

            if (score > bestScore) {
              bestScore = score;
              best = el;
            }
          }

          if (bestScore >= 6 && clickTarget(best)) {
            return true;
          }

          const links = Array.from(document.querySelectorAll('a[href]'));
          for (const link of links) {
            const href = normalize(link.getAttribute('href'));
            if (!href || !href.includes(year)) continue;

            const monthInHref = href.includes(monthFull) ||
              href.includes(monthShort) ||
              href.includes(`/${year}/${monthPadded}`) ||
              href.includes(`${monthPadded}${year}`);

            if (monthInHref || href.includes('statement') || href.includes('document') || href.includes('pdf')) {
              if (click(link)) return true;
            }
          }

          return false;
        })();
        """
    }

    public func triggerDownload() -> String {
        """
        (() => {
          const normalize = (value) => String(value || '')
            .toLowerCase()
            .replace(/\\s+/g, ' ')
            .trim();

          const click = (el) => {
            if (!el) return false;
            if (el.disabled === true) return false;
            try {
              el.scrollIntoView({ block: 'center', inline: 'nearest' });
            } catch (_) {}
            el.click();
            return true;
          };

          const textFor = (el) => normalize([
            el.innerText,
            el.textContent,
            el.getAttribute?.('aria-label'),
            el.getAttribute?.('title'),
            el.getAttribute?.('href'),
            el.value
          ].filter(Boolean).join(' '));

          const links = Array.from(document.querySelectorAll('a[href]'));
          for (const link of links) {
            const href = normalize(link.getAttribute('href'));
            if (href.endsWith('.pdf') || href.includes('/pdf') || href.includes('download')) {
              if (click(link)) return true;
            }
          }

          const candidates = Array.from(document.querySelectorAll(
            'button, a, [role="button"], input[type="button"], input[type="submit"]'
          ));

          let best = null;
          let bestScore = -1;

          for (const el of candidates) {
            const text = textFor(el);
            if (!text) continue;

            let score = 0;
            if (text.includes('download') || text.includes('view') || text.includes('open') || text.includes('print')) {
              score += 3;
            }
            if (text.includes('pdf')) score += 2;
            if (text.includes('statement') || text.includes('document')) score += 1;

            if (score > bestScore) {
              bestScore = score;
              best = el;
            }
          }

          if (bestScore >= 3 && click(best)) {
            return true;
          }

          return false;
        })();
        """
    }

    public func debugStatementSelectionSnapshot(month: Int, year: Int) -> String {
        """
        (() => {
          const months = [
            'january', 'february', 'march', 'april', 'may', 'june',
            'july', 'august', 'september', 'october', 'november', 'december'
          ];
          const monthIndex = Math.max(0, Math.min(11, \(month) - 1));
          const targetYear = String(\(year));
          const monthFull = months[monthIndex];
          const monthShort = monthFull.slice(0, 3);
          const monthNumber = String(monthIndex + 1);
          const monthPadded = monthNumber.padStart(2, '0');

          const normalize = (value) => String(value || '')
            .toLowerCase()
            .replace(/\\s+/g, ' ')
            .trim();

          const scoreCandidate = (text) => {
            let score = 0;
            if (text.includes(targetYear)) score += 2;
            if (text.includes(monthFull) || text.includes(monthShort)) score += 4;
            if (text.includes(`${monthNumber}/${targetYear}`) || text.includes(`${monthPadded}/${targetYear}`) || text.includes(`${targetYear}-${monthPadded}`)) {
              score += 4;
            }
            if (text.includes('statement') || text.includes('document')) score += 2;
            if (text.includes('pdf') || text.includes('download') || text.includes('view')) score += 2;
            return score;
          };

          const candidates = Array.from(document.querySelectorAll(
            'a, button, [role="button"], input[type="button"], input[type="submit"], tr, li, article, div[role="row"], div[data-testid]'
          ));

          const scored = candidates.map((el) => {
            const text = normalize([
              el.innerText,
              el.textContent,
              el.getAttribute?.('aria-label'),
              el.getAttribute?.('title'),
              el.getAttribute?.('data-testid'),
              el.getAttribute?.('data-label'),
              el.getAttribute?.('href'),
              el.value
            ].filter(Boolean).join(' '));

            return {
              tag: (el.tagName || '').toLowerCase(),
              score: scoreCandidate(text),
              text: text.slice(0, 220)
            };
          });

          scored.sort((a, b) => b.score - a.score);

          return JSON.stringify({
            url: location.href,
            title: document.title,
            target: { month: \(month), year: \(year) },
            topCandidates: scored.slice(0, 8)
          });
        })();
        """
    }

    public func debugDownloadSnapshot() -> String {
        """
        (() => {
          const normalize = (value) => String(value || '')
            .toLowerCase()
            .replace(/\\s+/g, ' ')
            .trim();

          const scoreCandidate = (text, href) => {
            let score = 0;
            if (href.endsWith('.pdf') || href.includes('/pdf') || href.includes('download')) score += 4;
            if (text.includes('download') || text.includes('view') || text.includes('open') || text.includes('print')) score += 3;
            if (text.includes('pdf')) score += 2;
            if (text.includes('statement') || text.includes('document')) score += 1;
            return score;
          };

          const candidates = Array.from(document.querySelectorAll(
            'button, a, [role="button"], input[type="button"], input[type="submit"]'
          ));

          const scored = candidates.map((el) => {
            const text = normalize([
              el.innerText,
              el.textContent,
              el.getAttribute?.('aria-label'),
              el.getAttribute?.('title'),
              el.getAttribute?.('href'),
              el.value
            ].filter(Boolean).join(' '));
            const href = normalize(el.getAttribute?.('href'));
            return {
              tag: (el.tagName || '').toLowerCase(),
              score: scoreCandidate(text, href),
              href: href.slice(0, 220),
              text: text.slice(0, 220)
            };
          });

          scored.sort((a, b) => b.score - a.score);

          return JSON.stringify({
            url: location.href,
            title: document.title,
            topCandidates: scored.slice(0, 8)
          });
        })();
        """
    }

    private func jsStringLiteral(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value]),
            var text = String(data: data, encoding: .utf8),
            text.count >= 2
        else {
            return "\"\""
        }

        text.removeFirst()
        text.removeLast()
        return text
    }
}
