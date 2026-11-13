# Dancing Totem

맥 메뉴바에서 GIF가 춤추는 앱입니다. CPU 사용량이 낮으면 천천히, 높아질수록 빠르게 움직입니다.

- CPU 0%에서 원래 속도의 0.25배, 100%에서 3배로 재생합니다.
- 원하는 GIF를 직접 골라 쓸 수 있습니다. GIF는 저장소에 들어 있지 않습니다.
- 앱 자체의 CPU 점유는 2% 안팎입니다.

## 요구 사항

- macOS 13 이상
- Xcode Command Line Tools (`xcode-select --install`)

## Homebrew로 설치

```bash
brew install syc030403/tap/dancing-totem
```

설치하는 맥에서 직접 컴파일합니다. 실행은 아래 명령으로 합니다.

```bash
dancing-totem
```

로그인할 때 자동으로 켜지게 하려면 아래 명령을 한 번 실행합니다.

```bash
brew services start dancing-totem
```

## 직접 빌드

```bash
./build.sh
open "build/Dancing Totem.app"
```

## 처음 실행

처음 실행하면 메뉴바에 "GIF 선택"이라는 글자가 나타납니다. 눌러서 **GIF 선택…** 을 고르고 재생할 GIF 파일을 지정하세요. 고른 파일은 `~/Library/Application Support/Dancing Totem/animation.gif` 로 복사됩니다.

빌드 전에 `Resources/dancer.gif` 를 넣어 두면 그 GIF가 앱에 기본으로 포함됩니다.

## 메뉴

| 항목 | 설명 |
| --- | --- |
| CPU: N% | 현재 CPU 사용량 |
| GIF 선택… | 재생할 GIF 변경 |
| 메뉴바에 CPU % 표시 | 그림 옆에 수치 표시 |
| 로그인 시 자동 실행 | 맥을 켤 때 자동으로 시작 |

메뉴의 자동 실행은 직접 빌드한 앱을 응용 프로그램 폴더로 옮긴 뒤에 켜세요. Homebrew로 설치했다면 `brew services` 를 쓰세요.

## GIF 고르는 요령

- 배경이 투명한 GIF가 가장 잘 어울립니다. 배경이 단색이면 자동으로 투명하게 처리합니다.
- 메뉴바 높이에 맞춰 16pt로 줄어들기 때문에 작고 단순한 그림이 잘 보입니다. 픽셀 아트를 권합니다.

## 설정 바꾸기

크기와 속도 범위는 `Sources/main.swift` 맨 위의 상수로 조정한 뒤 다시 빌드합니다.
