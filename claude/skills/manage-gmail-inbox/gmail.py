#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "google-api-python-client>=2.100",
#     "google-auth-oauthlib>=1.2",
# ]
# ///
"""Gmail inbox CLI — /manage-gmail-inbox 스킬의 백엔드.

의존성은 PEP 723 인라인 메타데이터로 선언돼 있어 `uv run` 이 격리 환경에 자동
설치한다. 시스템 python 에 아무것도 깔지 않는다.

설계 의도 — API 함정을 스킬 본문이 아니라 여기에 가둔다:

- **읽기는 읽음처리를 하지 않는다.** `users.messages.get` 은 UNREAD 라벨을 건드리지
  않으므로 본문을 열어도 안읽음이 유지된다. 읽음 상태가 바뀌는 것은 `mark` 뿐이다.
- **페이지네이션은 진짜로 동작한다.** `list` 는 nextPageToken 을 끝까지 따라가므로
  `--max` 를 넘지 않는 한 전량을 받는다.
- **목록 메타데이터는 배치로 받는다.** messages.list 는 id 만 주고 제목·발신자는
  메시지별 get 이 필요하다. 순차로 돌면 수십 초가 걸려 batch HTTP 로 100건씩 묶는다.
  httplib2 가 thread-safe 하지 않아 ThreadPoolExecutor 대신 batch 를 쓴다.
- **읽음처리는 batchModify 로 1000건까지 한 번에** 나간다.

인증 범위는 `gmail.modify` 다 — 라벨 조작은 되지만 영구 삭제는 되지 않는 범위라
스킬의 경계(삭제·발송 없음)가 토큰 수준에서 강제된다.

자격증명은 repo 밖 머신 로컬에 둔다:
    ~/.config/gmail-cli/credentials.json   (Google Cloud 에서 받은 OAuth 클라이언트)
    ~/.config/gmail-cli/token.json         (auth 가 생성)
$GMAIL_CLI_HOME 으로 위치를 바꿀 수 있다. 최초 설정은 SETUP.md 참조.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import html
import json
import os
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

SCOPES = ["https://www.googleapis.com/auth/gmail.modify"]
DEFAULT_QUERY = "is:unread -in:spam -in:trash"
BATCH_SIZE = 100          # Gmail batch HTTP 권장 상한
MODIFY_BATCH = 1000       # batchModify 하드 상한

EXIT_NO_CREDENTIALS = 3
EXIT_NEEDS_AUTH = 4
EXIT_API_ERROR = 5


def home() -> Path:
    return Path(os.environ.get("GMAIL_CLI_HOME", Path.home() / ".config" / "gmail-cli"))


def die(msg: str, code: int) -> None:
    print(msg, file=sys.stderr)
    sys.exit(code)


# --------------------------------------------------------------------------- auth


def load_service(interactive: bool = False, port: int = 0):
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build

    cred_path = home() / "credentials.json"
    token_path = home() / "token.json"

    creds = None
    if token_path.exists():
        creds = Credentials.from_authorized_user_file(str(token_path), SCOPES)

    if creds and creds.valid:
        return build("gmail", "v1", credentials=creds, cache_discovery=False)

    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            token_path.write_text(creds.to_json())
            token_path.chmod(0o600)
            return build("gmail", "v1", credentials=creds, cache_discovery=False)
        except Exception as e:  # refresh token 폐기(7일 미사용/비밀번호 변경 등)
            if not interactive:
                die(f"토큰 갱신 실패: {e}\n`gmail.py auth` 로 재인증하라.", EXIT_NEEDS_AUTH)

    if not interactive:
        die(
            f"인증 토큰이 없다({token_path}).\n`gmail.py auth` 를 먼저 실행하라.",
            EXIT_NEEDS_AUTH,
        )

    if not cred_path.exists():
        die(
            f"OAuth 클라이언트 파일이 없다: {cred_path}\n"
            "Google Cloud Console 에서 데스크톱 앱 클라이언트를 만들어 그 경로에 두어라 "
            "(절차는 스킬 폴더의 SETUP.md).",
            EXIT_NO_CREDENTIALS,
        )

    flow = InstalledAppFlow.from_client_secrets_file(str(cred_path), SCOPES)
    # 헤드리스/원격에서도 되도록 브라우저를 자동으로 열지 않고 URL 을 출력한다.
    # 포트를 고정할 수 있게 두는 이유: 승인 후 리다이렉트가 이 호스트의 localhost 로
    # 돌아와야 하는데, 원격 서버라면 포트를 알아야 SSH 포워딩이나 수동 전달을 할 수 있다.
    creds = flow.run_local_server(
        port=port,
        open_browser=False,
        authorization_prompt_message="브라우저에서 아래 URL 을 열어 승인하라:\n\n{url}\n",
        success_message="인증 완료. 터미널로 돌아가라.",
    )
    home().mkdir(parents=True, exist_ok=True)
    token_path.write_text(creds.to_json())
    token_path.chmod(0o600)
    print(f"토큰 저장: {token_path}", file=sys.stderr)
    return build("gmail", "v1", credentials=creds, cache_discovery=False)


# --------------------------------------------------------------------------- helpers


class _Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out: list[str] = []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "head"):
            self.skip += 1
        elif tag in ("br", "p", "div", "tr", "li", "h1", "h2", "h3"):
            self.out.append("\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "head") and self.skip:
            self.skip -= 1

    def handle_data(self, data):
        if not self.skip:
            self.out.append(data)


def html_to_text(raw: str) -> str:
    p = _Text()
    try:
        p.feed(raw)
    except Exception:
        return re.sub(r"<[^>]+>", " ", raw)
    return "".join(p.out)


def squeeze(text: str) -> str:
    text = html.unescape(text).replace("\r\n", "\n").replace("\xa0", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def b64(data: str) -> str:
    return base64.urlsafe_b64decode(data + "===").decode("utf-8", "replace")


def extract_body(payload: dict) -> str:
    """multipart 를 재귀 탐색해 text/plain 을 우선 수집하고, 없으면 html 을 텍스트로."""
    plain: list[str] = []
    rich: list[str] = []

    def walk(part: dict) -> None:
        mime = part.get("mimeType", "")
        body = part.get("body", {})
        data = body.get("data")
        if data:
            if mime == "text/plain":
                plain.append(b64(data))
            elif mime == "text/html":
                rich.append(html_to_text(b64(data)))
        for sub in part.get("parts", []):
            walk(sub)

    walk(payload)
    return squeeze("\n".join(plain) if plain else "\n".join(rich))


def headers_of(msg: dict) -> dict:
    return {
        h["name"].lower(): h["value"]
        for h in msg.get("payload", {}).get("headers", [])
    }


def when(msg: dict) -> str:
    ms = int(msg.get("internalDate", 0))
    return dt.datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M")


def label_map(service) -> dict[str, str]:
    labels = service.users().labels().list(userId="me").execute().get("labels", [])
    return {l["id"]: l["name"] for l in labels}


def pretty_labels(ids: list[str], names: dict[str, str]) -> str:
    """노이즈(UNREAD/INBOX)를 빼고 CATEGORY_ 접두어를 떼어 조밀하게."""
    out = []
    for lid in ids:
        if lid in ("UNREAD", "INBOX"):
            continue
        name = names.get(lid, lid)
        out.append(name.replace("CATEGORY_", "").lower())
    return ",".join(out)


def resolve_label(service, wanted: str) -> str:
    """라벨 이름(부분 일치, 대소문자 무시)을 라벨 id 로. id 를 그대로 줘도 통과."""
    labels = service.users().labels().list(userId="me").execute().get("labels", [])
    for l in labels:
        if l["id"] == wanted or l["name"].lower() == wanted.lower():
            return l["id"]
    hits = [l for l in labels if wanted.lower() in l["name"].lower()]
    if len(hits) == 1:
        return hits[0]["id"]
    if not hits:
        die(f"라벨을 찾을 수 없다: {wanted}", EXIT_API_ERROR)
    die(
        "라벨 이름이 모호하다: " + ", ".join(l["name"] for l in hits),
        EXIT_API_ERROR,
    )


def batch_get(service, ids: list[str], fmt: str, metadata_headers=None) -> list[dict]:
    """messages.get 을 batch HTTP 로 묶어 받는다. 순서는 입력 id 순으로 되돌린다."""
    from googleapiclient.errors import HttpError

    got: dict[str, dict] = {}
    errors: list[str] = []

    def collect(request_id, response, exception):
        if exception is not None:
            errors.append(f"{request_id}: {exception}")
        else:
            got[response["id"]] = response

    for i in range(0, len(ids), BATCH_SIZE):
        chunk = ids[i : i + BATCH_SIZE]
        batch = service.new_batch_http_request(callback=collect)
        for mid in chunk:
            kwargs = {"userId": "me", "id": mid, "format": fmt}
            if metadata_headers:
                kwargs["metadataHeaders"] = metadata_headers
            batch.add(service.users().messages().get(**kwargs), request_id=mid)
        try:
            batch.execute()
        except HttpError as e:
            die(f"배치 조회 실패: {e}", EXIT_API_ERROR)

    if errors:
        print(f"경고: {len(errors)}건 조회 실패\n  " + "\n  ".join(errors[:5]),
              file=sys.stderr)
    return [got[m] for m in ids if m in got]


# --------------------------------------------------------------------------- commands


def cmd_auth(args) -> None:
    if args.reauth:
        (home() / "token.json").unlink(missing_ok=True)
    service = load_service(interactive=True, port=args.port)
    profile = service.users().getProfile(userId="me").execute()
    print(f"인증 OK: {profile['emailAddress']} (총 {profile['messagesTotal']}통)")


def cmd_labels(args) -> None:
    service = load_service()
    labels = service.users().labels().list(userId="me").execute().get("labels", [])
    # list 는 카운트를 주지 않는다 — 라벨마다 get 이 필요해 배치로 묶는다.
    stats: dict[str, dict] = {}

    def collect(request_id, response, exception):
        if exception is None:
            stats[response["id"]] = response

    batch = service.new_batch_http_request(callback=collect)
    for l in labels:
        batch.add(
            service.users().labels().get(userId="me", id=l["id"]), request_id=l["id"]
        )
    batch.execute()

    rows = []
    for l in labels:
        s = stats.get(l["id"], {})
        unread = s.get("messagesUnread", 0)
        if unread or args.all:
            rows.append((unread, l["id"], l["name"], s.get("messagesTotal", 0)))
    rows.sort(reverse=True)

    if args.json:
        print(json.dumps(
            [{"unread": u, "id": i, "name": n, "total": t} for u, i, n, t in rows],
            ensure_ascii=False, indent=2))
        return
    if not rows:
        print("안읽은 메일 없음")
        return
    for unread, lid, name, total in rows:
        print(f"{unread:>6}\t{lid}\t{name}\t(전체 {total})")


def cmd_list(args) -> None:
    service = load_service()
    query = args.query
    label_ids = [resolve_label(service, args.label)] if args.label else None

    ids: list[str] = []
    token = None
    while True:
        req = service.users().messages().list(
            userId="me", q=query, labelIds=label_ids,
            maxResults=min(500, args.max - len(ids)), pageToken=token,
        )
        resp = req.execute()
        ids += [m["id"] for m in resp.get("messages", [])]
        token = resp.get("nextPageToken")
        if not token or len(ids) >= args.max:
            break
    ids = ids[: args.max]

    if not ids:
        print("해당 메일 없음" if not args.json else "[]")
        return

    msgs = batch_get(service, ids, "metadata",
                     ["From", "To", "Subject", "Date", "List-Id"])
    names = label_map(service)

    if args.by:
        # 대량 안읽음을 건별로 나열하면 컨텍스트가 터진다. 집계로 규모를 먼저 잡는다.
        from collections import Counter

        counter: Counter[str] = Counter()
        samples: dict[str, str] = {}
        for m in msgs:
            h = headers_of(m)
            sender = h.get("from", "(unknown)")
            if args.by == "domain":
                match = re.search(r"@([\w.-]+)", sender)
                key = match.group(1).lower() if match else sender
            elif args.by == "label":
                key = pretty_labels(m.get("labelIds", []), names) or "(none)"
            else:
                key = sender
            counter[key] += 1
            samples.setdefault(key, h.get("subject", ""))

        if args.json:
            print(json.dumps(
                [{"key": k, "count": c, "sampleSubject": samples[k]}
                 for k, c in counter.most_common()],
                ensure_ascii=False, indent=2))
            return
        print(f"# {len(msgs)}건 → {args.by} 별 {len(counter)}개 그룹")
        for key, count in counter.most_common():
            print(f"{count:>5}\t{key}\t{samples[key][:60]}")
        return

    if args.json:
        out = []
        for m in msgs:
            h = headers_of(m)
            out.append({
                "id": m["id"], "threadId": m["threadId"], "date": when(m),
                "from": h.get("from", ""), "to": h.get("to", ""),
                "subject": h.get("subject", "(제목 없음)"),
                "listId": h.get("list-id", ""),
                "labels": [names.get(x, x) for x in m.get("labelIds", [])],
                "unread": "UNREAD" in m.get("labelIds", []),
                "snippet": html.unescape(m.get("snippet", "")),
            })
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return

    print(f"# {len(msgs)}건  query={query!r}" + (f"  label={args.label}" if args.label else ""))
    for m in msgs:
        h = headers_of(m)
        sender = h.get("from", "")[:45]
        thread = "-" if m["threadId"] == m["id"] else m["threadId"]
        print("\t".join([
            m["id"], thread, when(m), sender,
            h.get("subject", "(제목 없음)"),
            pretty_labels(m.get("labelIds", []), names),
        ]))


def cmd_read(args) -> None:
    service = load_service()
    msgs = batch_get(service, args.ids, "full")
    names = label_map(service)
    limit = args.chars

    if args.json:
        out = []
        for m in msgs:
            h = headers_of(m)
            body = extract_body(m.get("payload", {}))
            out.append({
                "id": m["id"], "threadId": m["threadId"], "date": when(m),
                "from": h.get("from", ""), "to": h.get("to", ""),
                "cc": h.get("cc", ""), "subject": h.get("subject", ""),
                "labels": [names.get(x, x) for x in m.get("labelIds", [])],
                "unread": "UNREAD" in m.get("labelIds", []),
                "truncated": bool(limit and len(body) > limit),
                "body": body[:limit] if limit else body,
            })
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return

    for m in msgs:
        h = headers_of(m)
        body = extract_body(m.get("payload", {}))
        truncated = limit and len(body) > limit
        print(f"\n=== {m['id']} ===")
        print(f"From:    {h.get('from','')}")
        if h.get("to"):
            print(f"To:      {h['to']}")
        print(f"Date:    {when(m)}")
        print(f"Subject: {h.get('subject','(제목 없음)')}")
        print(f"Labels:  {pretty_labels(m.get('labelIds', []), names)}")
        print()
        print(body[:limit] if limit else body)
        if truncated:
            print(f"\n[... {len(body) - limit}자 잘림 — 전문은 --chars 0]")


def cmd_mark(args) -> None:
    service = load_service()
    add, remove = [], []
    if args.state == "read":
        remove = ["UNREAD"]
    elif args.state == "unread":
        add = ["UNREAD"]
    elif args.state == "star":
        add = ["STARRED"]
    elif args.state == "unstar":
        remove = ["STARRED"]

    ids = args.ids
    if args.dry_run:
        print(f"[dry-run] {len(ids)}건 → {args.state} (add={add} remove={remove})")
        return

    from googleapiclient.errors import HttpError

    done = 0
    failed: list[str] = []
    for i in range(0, len(ids), MODIFY_BATCH):
        chunk = ids[i : i + MODIFY_BATCH]
        try:
            service.users().messages().batchModify(
                userId="me",
                body={"ids": chunk, "addLabelIds": add, "removeLabelIds": remove},
            ).execute()
            done += len(chunk)
        except HttpError as e:
            failed += chunk
            print(f"실패 {len(chunk)}건: {e}", file=sys.stderr)

    print(f"{args.state}: 성공 {done}건" + (f" / 실패 {len(failed)}건" if failed else ""))
    if failed:
        sys.exit(EXIT_API_ERROR)


# --------------------------------------------------------------------------- main


def main() -> None:
    p = argparse.ArgumentParser(
        prog="gmail.py", description="Gmail inbox CLI (manage-gmail-inbox 스킬 백엔드)"
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("auth", help="OAuth 인증(최초 1회) / 토큰 확인")
    a.add_argument("--reauth", action="store_true", help="기존 토큰을 버리고 재인증")
    a.add_argument("--port", type=int, default=0,
                   help="OAuth 콜백 수신 포트. 원격/헤드리스에서는 고정 포트를 줘라 (기본: 임의)")
    a.set_defaults(func=cmd_auth)

    l = sub.add_parser("labels", help="라벨별 안읽은 수")
    l.add_argument("--all", action="store_true", help="안읽은 수가 0 인 라벨도 표시")
    l.add_argument("--json", action="store_true")
    l.set_defaults(func=cmd_labels)

    ls = sub.add_parser("list", help="메일 목록(기본: 안읽음 전체)")
    ls.add_argument("-q", "--query", default=DEFAULT_QUERY, help=f"Gmail 검색 쿼리 (기본 {DEFAULT_QUERY!r})")
    ls.add_argument("-l", "--label", help="라벨 이름 또는 id 로 한정")
    ls.add_argument("-n", "--max", type=int, default=500, help="최대 건수 (기본 500)")
    ls.add_argument("--by", choices=["sender", "domain", "label"],
                    help="건별 나열 대신 집계만 출력 (대량 안읽음의 규모 파악용)")
    ls.add_argument("--json", action="store_true")
    ls.set_defaults(func=cmd_list)

    r = sub.add_parser("read", help="본문 읽기 (읽음처리 안 됨)")
    r.add_argument("ids", nargs="+")
    r.add_argument("-c", "--chars", type=int, default=2000, help="본문 길이 제한, 0=무제한 (기본 2000)")
    r.add_argument("--json", action="store_true")
    r.set_defaults(func=cmd_read)

    m = sub.add_parser("mark", help="읽음/안읽음/별표 변경")
    m.add_argument("state", choices=["read", "unread", "star", "unstar"])
    m.add_argument("ids", nargs="+")
    m.add_argument("--dry-run", action="store_true")
    m.set_defaults(func=cmd_mark)

    args = p.parse_args()
    try:
        args.func(args)
    except KeyboardInterrupt:
        sys.exit(130)


if __name__ == "__main__":
    main()
