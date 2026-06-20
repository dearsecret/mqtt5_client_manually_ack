# mqtt5_client_manually_ack

본 프로젝트는 [mqtt5_client](https://github.com/shamblett/mqtt5_client) 라이브러리를 기반으로, **QoS 1 메시지에 대한 수동 ACK(Manual Acknowledgement)** 기능을 추가한 커스텀 버전입니다.

## 개요

기존 라이브러리는 MQTT 프로토콜 표준에 따라 QoS 1 메시지 수신 시 자동으로 `PUBACK`를 반환합니다. 본 버전은 비즈니스 로직 처리가 완료된 후 개발자가 직접 `PUBACK`를 제어할 수 있도록 하여, 데이터 처리의 안정성을 높이고 흐름 제어를 최적화할 수 있도록 설계되었습니다.

## 주요 기능

- **수동 ACK 모드**: `manuallyAcknowledgeQos1` 설정을 통해 ACK 시점을 제어 가능.
- **안전한 데이터 처리**: 처리되지 않은 QoS 1 메시지는 내부 큐(`pendingQos1Messages`)에 안전하게 저장.

## 사용법

### 1. 설정

수동 ACK 모드를 활성화합니다.

```dart
client.manuallyAcknowledgeQos1 = true;
```
