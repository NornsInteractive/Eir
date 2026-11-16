#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import csv
import sys

CSV_PATH = 'listingData-9ND3DBN81QNC-1152921505702417629.csv'

# Translations dictionary
DATA = {
    'Description': {
        'zh-hans': '异地同屏放映室：60 FPS 极速屏幕共享、毫秒级音视频同步观影。免注册免登录，双向语音通话，端到端 P2P 隐私保护。',
        'en': 'Synchronized watch party theater: 60 FPS ultra-fast screen sharing and millisecond-level video co-watching. No login or registration required, real-time two-way voice chat, and end-to-end P2P privacy protection.',
        'zh-hant': '異地同屏放映室：60 FPS 極速螢幕共享、毫秒級音視頻同步觀影。免註冊免登入，雙向語音通話，端到端 P2P 隱私保護。',
        'ja': 'リモート同時視聴シアター：60 FPS 超高速画面共有＆ミリ秒単位の動画同期視聴。登録・ログイン不要、双方向ボイスチャット、エンドツーエンドP2Pプライバシー保護。',
        'ko': '원격 동시 시청 시네마: 60 FPS 초고속 화면 공유 및 밀리초 단위 비디오 동기화 시청. 회원가입 및 로그인 불필요, 양방향 음성 채팅, 종단간 P2P 개인정보 보호.',
        'de': 'Synchronisiertes Watch-Party-Kino: 60 FPS ultraschnelle Bildschirmübertragung und Co-Watching in Millisekundengenauigkeit. Keine Registrierung oder Anmeldung erforderlich, bidirektionaler Sprachchat und durchgehender P2P-Datenschutz.',
        'fr': "Cinéma Watch Party synchronisé : partage d'écran ultra-rapide à 60 FPS et visionnage vidéo synchronisé à la milliseconde. Sans inscription ni connexion, chat vocal bidirectionnel et protection de la vie privée P2P de bout en bout.",
        'es': 'Cine Watch Party sincronizado: uso compartido de pantalla ultrarrápido a 60 FPS y visualización de video sincronizada al milisegundo. Sin registro ni inicio de sesión, chat de voz bidireccional y privacidad P2P de extremo a extremo.',
        'pt': 'Cinema Watch Party sincronizado: compartilhamento de tela ultrarrápido a 60 FPS e reprodução de vídeo sincronizada ao milissegundo. Sem cadastro ou login, chat de voz bidirecional e privacidade P2P de ponta a ponta.',
        'ru': 'Синхронный кинозал Watch Party: сверхбыстрая демонстрация экрана 60 FPS и совместный просмотр видео с точностью до миллисекунд. Без регистрации и входа, двусторонняя голосовая связь и сквозная P2P-защита конфиденциальности.',
    },
    'Feature1': {
        'zh-hans': '毫秒级播放进度同步：本地视频与网络串流全员毫秒级同步放映',
        'en': 'Millisecond-level sync: High-precision co-watching for local video files and network streams.',
        'zh-hant': '毫秒級播放進度同步：本機影片與網路串流全員毫秒級同步放映',
        'ja': 'ミリ秒精度の再生同期：ローカル動画ファイルとネット配信の超高精度な同時再生',
        'ko': '밀리초 단위 재생 동기화: 로컬 비디오 및 네트워크 스트리밍의 초정밀 실시간 동기화',
        'de': 'Millisekundengenaue Wiedergabesynchronisation: Perfektes Co-Watching für lokale Videodateien und Web-Streams.',
        'fr': 'Synchronisation à la milliseconde : Lecture parfaitement synchronisée des fichiers vidéo locaux et des flux web.',
        'es': 'Sincronización al milisegundo: Reproducción coordinada de archivos de video locales y transmisiones web.',
        'pt': 'Sincronização ao milissegundo: Co-visualização de alta precisão para arquivos de vídeo locais e transmissões web.',
        'ru': 'Синхронизация с точностью до миллисекунд: Идеально синхронный просмотр локальных видеофайлов и веб-трансляций.',
    },
    'Feature2': {
        'zh-hans': '60 FPS 极速屏幕共享：高清桌面与窗口捕获，支持系统声音内录同传',
        'en': '60 FPS screen sharing: High-definition desktop and window capture with native system audio pass-through.',
        'zh-hant': '60 FPS 極速螢幕共享：高畫質桌面與視窗擷取，支援系統聲音內錄同傳',
        'ja': '60 FPS 高速画面共有：高画質な画面・ウィンドウ共有とシステム音声のダイレクト配信',
        'ko': '60 FPS 초고속 화면 공유: 고화질 데스크톱/창 캡처 및 시스템 오디오 직접 전송',
        'de': '60 FPS Bildschirmübertragung: HD-Desktop- und Fensteraufnahme mit direkter Systemton-Übertragung.',
        'fr': "Partage d'écran 60 FPS : Capture HD du bureau et des fenêtres avec transmission directe de l'audio système.",
        'es': 'Compartir pantalla a 60 FPS: Captura HD de escritorio y ventanas con transmisión directa de audio del sistema.',
        'pt': 'Compartilhamento de tela a 60 FPS: Captura em HD da área de trabalho e janelas com áudio do sistema direto.',
        'ru': 'Демонстрация экрана 60 FPS: Захват рабочего стола и окон в HD-качестве с прямой передачей системного звука.',
    },
    'Feature3': {
        'zh-hans': '实时双向低延迟语音通话：边看边聊，沟通零障碍',
        'en': 'Real-time two-way voice chat: Ultra-low latency voice communication while watching together.',
        'zh-hant': '即時雙向低延遲語音通話：邊看邊聊，溝通零障礙',
        'ja': 'リアルタイム双方向ボイス通話：動画を見ながら低遅延でスムーズに通話可能',
        'ko': '실시간 양방향 음성 채팅: 영상을 보면서 지연 없는 원활한 음성 대화 지원',
        'de': 'Echtzeit-Sprachchat: Kristallklare, latenzarme Zwei-Wege-Sprachkommunikation beim gemeinsamen Schauen.',
        'fr': 'Chat vocal bidirectionnel en direct : Communication vocale fluide à faible latence pendant le visionnage.',
        'es': 'Chat de voz bidireccional en tiempo real: Comunicación por voz de baja latencia mientras disfrutan del video.',
        'pt': 'Chat de voz bidirecional em tempo real: Comunicação de voz com baixíssima latência enquanto assistem juntos.',
        'ru': 'Голосовой чат в реальном времени: Общение с минимальной задержкой прямо во время просмотра.',
    },
    'Feature4': {
        'zh-hans': '纯粹免注册免登录：6 位房间码一秒入会，用完即走',
        'en': 'Zero registration & no login: Join instantly via a 6-digit room code with complete ease.',
        'zh-hant': '純粹免註冊免登入：6 位房間代碼一秒入會，用完即走',
        'ja': '登録・ログイン不要：6桁のルームコードを入力するだけで瞬時に参加可能',
        'ko': '회원가입 및 로그인 없음: 6자리 룸 코드로 1초 만에 간편 입장',
        'de': 'Keine Anmeldung nötig: Sofortiger Beitritt mit einem 6-stelligen Raumcode ohne Registrierung.',
        'fr': 'Sans inscription ni connexion : Rejoignez instantanément une salle avec un code à 6 chiffres.',
        'es': 'Sin registro ni cuenta: Únete al instante mediante un código de sala de 6 dígitos con total facilidad.',
        'pt': 'Sem registro nem login: Entre instantaneamente usando um código de sala de 6 dígitos.',
        'ru': 'Без регистрации и учетных записей: Мгновенный вход в комнату по 6-значному коду.',
    },
    'Feature5': {
        'zh-hans': '端到端 P2P 加密：媒体流量直连传输，数据绝不上云',
        'en': 'End-to-end P2P encryption: Direct peer-to-peer media pipeline with zero cloud storage.',
        'zh-hant': '端到端 P2P 加密：媒體流量直連傳輸，資料絕不上雲',
        'ja': 'エンドツーエンドP2P暗号化：直接P2P通信でクラウドにデータを残さない安心設計',
        'ko': '종단간 P2P 암호화: 클라우드 저장 없는 다이렉트 P2P 전송으로 철저한 보안',
        'de': 'Ende-zu-Ende P2P-Verschlüsselung: Direkte Peer-to-Peer-Datenübertragung ohne Cloud-Speicherung.',
        'fr': 'Chiffrement P2P de bout en bout : Flux multimédia direct entre pairs sans aucun stockage dans le cloud.',
        'es': 'Cifrado P2P de extremo a extremo: Transmisión directa entre pares sin almacenamiento en la nube.',
        'pt': 'Criptografia P2P de ponta a ponta: Transmissão direta peer-to-peer sem dados armazenados na nuvem.',
        'ru': 'Сквозное P2P-шифрование: Прямой обмен медиапотоками между устройствами без сохранения в облаке.',
    },
    'Feature6': {
        'zh-hans': '互动弹幕与文字聊天：彩色弹幕漂浮，营造真实放映厅互动氛围',
        'en': 'Interactive floating bullet chat: Colorful real-time bullet comments for an authentic theater experience.',
        'zh-hant': '互動彈幕與文字聊天：彩色彈幕漂浮，營造真實放映廳互動氛圍',
        'ja': 'インタラクティブ弾幕チャット：画面上を流れるカラフルなコメントで劇場のような臨場感',
        'ko': '실시간 탄막 및 텍스트 채팅: 화면에 흐르는 다채로운 탄막으로 극장 같은 현장감 제공',
        'de': 'Interaktiver Danmaku-Chat: Bunte, schwebende Live-Kommentare für echte Kinoatmosphäre.',
        'fr': "Chat flottant interactif : Commentaires animés à l'écran pour une ambiance de salle de cinéma.",
        'es': 'Comentarios flotantes interactivos: Mensajes dinámicos en pantalla para crear un ambiente de cine real.',
        'pt': 'Chat flutuante interativo: Comentários coloridos na tela para recriar a verdadeira atmosfera de cinema.',
        'ru': 'Интерактивные всплывающие комментарии: Живые цветные субтитры на экране для создания атмосферы кинотеатра.',
    },
    'SearchTerm1': {
        'zh-hans': '同步观影',
        'en': 'Watch Party',
        'zh-hant': '同步觀影',
        'ja': '同時視聴',
        'ko': '동시시청',
        'de': 'Watch Party',
        'fr': 'Watch Party',
        'es': 'Watch Party',
        'pt': 'Watch Party',
        'ru': 'Watch Party',
    },
    'SearchTerm2': {
        'zh-hans': '屏幕共享',
        'en': 'Screen Sharing',
        'zh-hant': '螢幕共享',
        'ja': '画面共有',
        'ko': '화면공유',
        'de': 'Bildschirmübertragung',
        'fr': "Partage d'écran",
        'es': 'Compartir pantalla',
        'pt': 'Compartilhar tela',
        'ru': 'Демонстрация экрана',
    },
    'SearchTerm3': {
        'zh-hans': '一起看视频',
        'en': 'Co-watching',
        'zh-hant': '一起看影片',
        'ja': 'ウォッチパーティー',
        'ko': '워치파티',
        'de': 'Gemeinsam schauen',
        'fr': 'Regarder ensemble',
        'es': 'Ver juntos',
        'pt': 'Assistir juntos',
        'ru': 'Совместный просмотр',
    },
    'SearchTerm4': {
        'zh-hans': '异地放映室',
        'en': 'Sync Video',
        'zh-hant': '異地放映室',
        'ja': '動画同期',
        'ko': '영상동기화',
        'de': 'Videosynchronisation',
        'fr': 'Synchro vidéo',
        'es': 'Sincronizar video',
        'pt': 'Sincronizar vídeo',
        'ru': 'Синхронизация видео',
    },
    'SearchTerm5': {
        'zh-hans': '投屏',
        'en': 'Screen Mirror',
        'zh-hant': '投影',
        'ja': 'スクリーンシェア',
        'ko': '스크린셰어',
        'de': 'Screen Share',
        'fr': 'Screen Share',
        'es': 'Screen Share',
        'pt': 'Screen Share',
        'ru': 'Трансляция экрана',
    },
    'SearchTerm6': {
        'zh-hans': 'WebRTC',
        'en': 'WebRTC',
        'zh-hant': 'WebRTC',
        'ja': 'WebRTC',
        'ko': 'WebRTC',
        'de': 'WebRTC',
        'fr': 'WebRTC',
        'es': 'WebRTC',
        'pt': 'WebRTC',
        'ru': 'WebRTC',
    },
    'SearchTerm7': {
        'zh-hans': 'WatchParty',
        'en': 'WatchParty',
        'zh-hant': 'WatchParty',
        'ja': 'WatchParty',
        'ko': 'WatchParty',
        'de': 'WatchParty',
        'fr': 'WatchParty',
        'es': 'WatchParty',
        'pt': 'WatchParty',
        'ru': 'WatchParty',
    },
}

# Set default column to english for all translated fields
for k in DATA:
    DATA[k]['default'] = DATA[k]['en']

# Constants across all language columns
CONSTANTS = {
    'Title': 'Eir-Synchronized Watch Party',
    'DevStudio': 'Norns',
    'CopyrightTrademarkInformation': 'Copyright © 2026 Norns Interactive. All rights reserved.',
    'DesktopScreenshot1': 'https://developer.microsoft.com/en-us/dashboard/apps/9ND3DBN81QNC/submissions/1152921505702417629/listings/1152922700029815381/listingassets/3027959311944589886',
    'DesktopScreenshot2': 'https://developer.microsoft.com/en-us/dashboard/apps/9ND3DBN81QNC/submissions/1152921505702417629/listings/1152922700029815381/listingassets/3026384645476649342',
    'DesktopScreenshot3': 'https://developer.microsoft.com/en-us/dashboard/apps/9ND3DBN81QNC/submissions/1152921505702417629/listings/1152922700029815381/listingassets/3005711445921076227',
    'OverrideLogosForWin10': 'False',
}

def main():
    with open(CSV_PATH, mode='r', encoding='utf-8-sig') as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)

    print(f"Loaded {len(rows)} rows from {CSV_PATH}")
    lang_cols = header[3:] # ['default', 'zh-hans', 'en', 'zh-hant', 'ja', 'ko', 'de', 'fr', 'es', 'pt', 'ru']
    print(f"Languages: {lang_cols}")

    updated_count = 0
    for row in rows:
        field_name = row[0]
        if field_name in CONSTANTS:
            val = CONSTANTS[field_name]
            for idx, lang in enumerate(lang_cols, start=3):
                row[idx] = val
            updated_count += 1
        elif field_name in DATA:
            field_dict = DATA[field_name]
            for idx, lang in enumerate(lang_cols, start=3):
                if lang in field_dict:
                    row[idx] = field_dict[lang]
                else:
                    row[idx] = field_dict.get('en', '')
            updated_count += 1

    print(f"Updated {updated_count} fields across {len(lang_cols)} language columns.")

    tmp_path = CSV_PATH + '.tmp'
    with open(tmp_path, mode='w', encoding='utf-8-sig', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)

    import os
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    os.rename(tmp_path, CSV_PATH)

    print("File saved successfully with UTF-8 BOM encoding.")

if __name__ == '__main__':
    main()
