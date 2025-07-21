import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class TermuxService {
  Future<bool> isTermuxInstalled() async {
    try {
      AndroidIntent intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        package: 'com.termux',
      );
      await intent.launch();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> launchTermuxAndRunScript() async {
    if (await Permission.storage.request().isGranted) {
      final script = await _createSetupScript();
      final intent = AndroidIntent(
        action: 'android.intent.action.RUN',
        package: 'com.termux',
        arguments: {'com.termux.execute.path': script.path},
      );
      await intent.launch();
    }
  }

  Future<File> _createSetupScript() async {
    final directory = await getTemporaryDirectory();
    final scriptFile = File('${directory.path}/setup_and_run.sh');
    final script = """
#!/data/data/com.termux/files/usr/bin/bash
pkg update -y && pkg upgrade -y
pkg install -y git wget cmake python tmux
if [ ! -d "llama.cpp" ]; then
    git clone https://github.com/ggerganov/llama.cpp
    cd llama.cpp && make
fi
mkdir -p llama.cpp/models
if [ ! -f "llama.cpp/models/tinyllama-1.1b.Q4_K_M.gguf" ]; then
    wget https://huggingface.co/TheBloke/TinyLlama-1.1B-1T-OpenOrca-GGUF/resolve/main/tinyllama-1.1b-1t-openorca.Q4_K_M.gguf -O llama.cpp/models/tinyllama-1.1b.Q4_K_M.gguf
fi
cd llama.cpp
tmux new -d -s ollama_api './server -m models/tinyllama-1.1b.Q4_K_M.gguf --port 8080 --threads 4'
""";
    await scriptFile.writeAsString(script);
    return scriptFile;
  }
}
