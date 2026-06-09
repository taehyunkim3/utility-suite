# Utility Suite

macOS에서 이미지 WebP 변환, 영상/음성 파일의 음원 추출, PDF 페이지 이미지 추출을 처리하는 작은 데스크톱 앱입니다.

## 기능

- PNG, JPG, JPEG 파일을 WebP로 일괄 변환
- MP4, MOV, MKV, M4A 등에서 오디오만 추출
- PDF의 각 페이지를 PNG, JPEG, WebP 이미지 파일로 추출

## WebP 인코더 포함

앱 번들에는 macOS arm64용 `cwebp` 실행 파일과 필요한 동적 라이브러리가 포함됩니다. 따라서 배포된 `Utility Suite.app`을 사용하는 사람은 WebP 변환을 위해 Homebrew나 `webp` 패키지를 따로 설치하지 않아도 됩니다.

포함된 오픈소스 구성요소와 라이선스 원문은 `ThirdParty/cwebp/NOTICE.md`와 `ThirdParty/cwebp/licenses/`에서 확인할 수 있습니다. 패키징된 앱에서는 `Utility Suite.app/Contents/Resources/ThirdPartyLicenses/cwebp/`에 복사되며, 앱 메뉴의 `오픈소스 라이선스` 항목으로도 열 수 있습니다.

## 개발 실행

```zsh
swift run WebPDrop
```

## 앱 패키징

아래 명령을 실행하면 vendored `cwebp`와 라이선스 파일을 포함한 `dist/Utility Suite.app`이 만들어집니다.

```zsh
./scripts/package-app.sh
```

## 공유용 zip 만들기

앱 번들을 만든 뒤 아래 명령으로 zip 파일을 생성합니다.

```zsh
ditto -c -k --keepParent "dist/Utility Suite.app" dist/UtilitySuite.zip
```

생성된 파일:

```text
dist/UtilitySuite.zip
```

이 zip 파일을 다른 사람에게 전달하면 됩니다.

## 미서명 앱 실행 안내

현재 앱은 Apple Developer ID로 정식 서명 및 공증된 앱이 아닙니다. 그래서 다른 Mac에서 처음 실행할 때 "확인되지 않은 개발자" 또는 "손상되었기 때문에 열 수 없음" 같은 경고가 뜰 수 있습니다.

받는 사람은 보통 아래 순서로 실행할 수 있습니다.

1. `UtilitySuite.zip` 압축을 풉니다.
2. `Utility Suite.app`을 `Applications` 폴더로 옮깁니다.
3. 앱을 더블클릭하지 말고, 우클릭 또는 Control-클릭 후 `열기`를 선택합니다.
4. macOS 보안 경고에서 다시 `열기`를 선택합니다.

그래도 실행이 막히면 터미널에서 아래 명령을 실행합니다.

```zsh
xattr -dr com.apple.quarantine "/Applications/Utility Suite.app"
```

## 정식 배포

여러 사람에게 일반 앱처럼 배포하려면 Apple Developer 계정으로 `Developer ID Application` 인증서를 발급받고, 앱 서명과 notarization을 진행해야 합니다.

대략적인 흐름은 다음과 같습니다.

```zsh
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: 이름 (TEAMID)" \
  "dist/Utility Suite.app"

ditto -c -k --keepParent "dist/Utility Suite.app" dist/UtilitySuite.zip

xcrun notarytool submit dist/UtilitySuite.zip \
  --apple-id "애플ID" \
  --team-id "TEAMID" \
  --password "앱 전용 비밀번호" \
  --wait

xcrun stapler staple "dist/Utility Suite.app"
```
