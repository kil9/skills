"""덱 설정. build.py·check.py 가 읽는다. 이 파일과 content/ 를 새 프로젝트 디렉터리로 복사해 시작한다."""
TITLE = "DB 인덱스 강좌"
DECKS = {1: "인덱스는 왜 읽기를 빠르게 하나"}
LECTURE = True            # 강의형: 덱마다 요약·확인 문제·정답 필수
TOTAL = (4, 40)           # 총 장수 범위(착수 때 정한 분량)
EXTRA_BANNED: list[str] = []
EXTRA_WARN: dict[str, str] = {}
