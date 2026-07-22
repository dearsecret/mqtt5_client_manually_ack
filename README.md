# mqtt5_client_custom

본 프로젝트는 [mqtt5_client](https://github.com/shamblett/mqtt5_client) 라이브러리를 기반으로, 모바일 환경에 최적화된 안정성 기능을 추가한 커스텀 버전입니다.

본 프로젝트의 커스텀 코드 및 추가된 보안 아키텍처는 원저작자의 라이선스 정책을 준수하며, 프로젝트 루트의 LICENSE 파일을 따릅니다.

## 주요 개선 기능

### 1. 비동기 재연결 제어 (Async Reconnect Control)

기존 이벤트 버스 방식 대신 `onFailedConnectionAttempt`를 비동기로 제어하여, 재연결 시퀀스를 사용자가 직접 제어합니다. 토큰 갱신 등 비동기 작업이 완료될 때까지 재연결을 대기시켜 안정성을 극대화합니다.

### 2. 수동 ACK 모드 (Manual Acknowledgement)

비즈니스 로직 처리가 완료된 후 개발자가 직접 `PUBACK`를 반환하여 데이터 유실을 방지합니다.

## 사용법

### Manually PUBACK

```dart
client.manuallyAcknowledgeQos1 = true;


```
