// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:project_app/audio/audio.dart';
import 'package:project_app/audio/classifier.dart';
import 'package:project_app/entry.dart';
import 'package:random_color/random_color.dart';
import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

import 'audio/main.dart';

enum Direction {
  // ignore: constant_identifier_names
  Right,
  // ignore: constant_identifier_names
  Left,
  // ignore: constant_identifier_names
  Idle,
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

const sampleRate = 8000;

class _MyAppState extends State<MyApp> {
  RandomColor randomColorGen = RandomColor();

  UsbPort? _port;
  String _status = "Idle";
  List<Widget> _ports = [];
  List<Widget> _serialData = [];
  final List<int> _data = [];
  late final ScrollController _controller;
  late Stream<String> lines;

  ///
  final List<int> _chunks = [];
  late final StreamController<List<int>> _analogChunks;

  //for classifier

  late Timer _timer;

  late Classifier _classifier;

  List<Category> preds = [];

  // RandomColor randomColorGen = RandomColor();

  Category? prediction;

  late StreamController<List<Category>> streamController;

  ////////////////

  StreamSubscription<String>? _subscription;
  Transaction<String>? _transaction;
  UsbDevice? _device;

  final audioSampleRate = 16000;

  final TextEditingController _textController = TextEditingController();
  var direction = Direction.Idle;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();

    _analogChunks = StreamController<List<int>>();
    UsbSerial.usbEventStream!.listen((UsbEvent event) {
      _getPorts();
      print("object");
    });

    _getPorts();

///////////////
    streamController = StreamController();

    // initPlugin();
    init();
    Future.delayed(const Duration(seconds: 5)).then((value) {
      _timer = Timer.periodic(const Duration(seconds: 2), (Timer t) {
        streamController.add(_classifier.predict(_data));
      });
    });
  }

  Future<void> initPlugin() async {
    // _audioStream = _recorder.audioStream.listen((data) {
  }

  Future<void> init() async {
    _classifier = Classifier();
    await _classifier.loadModel();
    await _classifier.loadLabels();
  }

  ////
  ///
  Future<void> openFileAndRead() async {
    if (await Permission.storage.request().isGranted) {
      File file = File("/storage/emulated/0/Download/data.txt");
      lines = file
          .openRead()
          .transform(utf8.decoder) // Decode bytes to UTF-8.
          .transform(const LineSplitter());
      // lines.listen((line) {
      for (var byte in Audio.samples) {
        _chunks.add(byte);
        if (_chunks.length > 2555) {
          _analogChunks.add(Uint8List.fromList(_chunks));
          _chunks.clear();
        }

        // });

        setState(() {
          _serialData.add(Text(byte.toString()));
          // if (_serialData.length > 20) {
          //   _serialData.removeAt(0);
          // }
        });
      }

      _analogChunks.stream.listen((event) {
        print(event);
        if (_data.length > audioSampleRate) {
          print(_data.length);
          _data.clear();
        }
        log(event.toString());
        _data.addAll(event);
      });
      streamController.stream.listen((event) {
        setState(() {
          preds = event;
        });
      });
    }
  }

  void setDirection(String directionAsString) {
    if (directionAsString == " RIGHT") {
      direction = Direction.Right;
    } else {
      direction = Direction.Left;
    }
    setState(() {});
    Future.delayed(
      const Duration(milliseconds: 200),
      () {
        direction = Direction.Idle;
        setState(() {});
      },
    );
  }

  void closeAllNeccesary() {
    if (_subscription != null) {
      _subscription!.cancel();
      streamController.close();
      _subscription = null;
    }

    if (_transaction != null) {
      _transaction!.dispose();
      _transaction = null;
    }

    if (_port != null) {
      _port!.close();
      _port = null;
    }
  }

  Future<void> setPorts(UsbPort? port) async {
    await port!.setDTR(true);
    await port.setRTS(true);
    await port.setPortParameters(
        115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
  }

  Future<bool> _connectTo(device) async {
    _serialData.clear();
    closeAllNeccesary();

    if (device == null) {
      _device = null;
      setState(() {
        _status = "Disconnected";
      });
      return true;
    }

    _port = await device.create();
    if (await (_port!.open()) != true) {
      setState(() {
        _status = "Failed to open port";
      });
      return false;
    }
    _device = device;

    await setPorts(_port);
    _transaction = Transaction.stringTerminated(
        _port!.inputStream as Stream<Uint8List>, Uint8List.fromList([13, 10]));

    _subscription = _transaction!.stream.listen((String line) {
      final l = line.split(":");
      if (line.length > 20) {
        setState(() {
          _serialData.add(Text(line));
          // log(l.last);
          setDirection(l.last);
        });
      } else {
        final byte = () {
          // return int.parse(line);
          if (l.length < 2) {
            return int.parse(l.first);
          } else {
            return int.parse(l[1]);
          }
        }();
        _chunks.add(byte);
        if (_chunks.length > 1200) {
          ByteData byteData = ByteData(_chunks.length * 2);
          for (int i = 0; i < _chunks.length; i++) {
            // byteData.setUint64(byteOffset, value)
            byteData.setUint16(i * 2, _chunks[i], Endian.little);
          }
          // _analogChunks.add(_chunks);
          _analogChunks.add(byteData.buffer.asUint8List());
          log(_chunks.toString());
          _chunks.clear();
        }
      }
    });
    await Future.delayed(const Duration(milliseconds: 1500));

    _analogChunks.stream.listen((event) {
      // log(event.toString());
      if (_data.length > 2 * sampleRate) {
        print(_data.length);
        _data.clear();
      }
      _data.addAll(event);
      log(event.toString());
    });
    streamController.stream.listen((event) {
      setState(() {
        preds = event;
      });
    });

    setState(() {
      _status = "Connected";
    });
    return true;
  }

  List<UsbDevice> devices = [];

  void _getPorts() async {
    _ports = [];
    devices = await UsbSerial.listDevices();
    if (!devices.contains(_device)) {
      _connectTo(null);
    }
    print(devices);

    devices.forEach((device) {
      _ports.add(ListTile(
          leading: Icon(Icons.usb),
          title: Text(device.productName!),
          subtitle: Text(device.manufacturerName!),
          trailing: ElevatedButton(
            child: Text(_device == device ? "Disconnect" : "Connect"),
            onPressed: () {
              _connectTo(_device == device ? null : device).then((res) {
                _getPorts();
              });
            },
          )));
    });

    setState(() {
      print(_ports);
    });
  }

  @override
  void dispose() {
    super.dispose();
    streamController.close();
    _analogChunks.close();
    _connectTo(null);
  }

  @override
  Widget build(BuildContext context) {
    print(devices);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: EntryWidget.blockHeight * 10,
          ),
          SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.rotate(
                  angle: 3.1,
                  child: Icon(
                    Icons.forward,
                    color: direction == Direction.Left
                        ? Colors.green
                        : Colors.white.withOpacity(.5),
                    size: EntryWidget.blockWidth * 60,
                  ),
                ),
                Icon(
                  Icons.forward,
                  color: direction == Direction.Right
                      ? Colors.green
                      : Colors.white.withOpacity(.5),
                  size: EntryWidget.blockWidth * 60,
                ),
              ],
            ),
          ),
          SizedBox(height: EntryWidget.blockHeight * 3),
          if (preds.isNotEmpty && _status == "Connected")
            SizedBox(
              child: Column(
                children: [
                  Text(
                    preds.first.label,
                    style: TextStyle(
                      fontSize: EntryWidget.blockWidth * 10,
                      color: Colors.orange.withOpacity(.8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    preds[1].label,
                    style: TextStyle(
                      fontSize: EntryWidget.blockWidth * 4,
                      color: Colors.red.withOpacity(.7),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: EntryWidget.blockHeight * 3),
          if (devices.isEmpty)
            Text(
              "No device available.",
              style: TextStyle(
                color: Colors.white,
                fontSize: EntryWidget.blockWidth * 3,
              ),
            ),
          if (devices.isNotEmpty && _status == "Disconnected")
            Text(
              "Please connect to available device",
              style: TextStyle(
                color: Colors.white,
                fontSize: EntryWidget.blockWidth * 3,
              ),
            ),
          SizedBox(height: EntryWidget.blockHeight * 5),
          GestureDetector(
            onTap: devices.isEmpty
                ? null
                : () {
                    _connectTo(_device == devices.first ? null : devices.first)
                        .then((res) {
                      _getPorts();
                    });
                  },
            child: Container(
              height: EntryWidget.blockHeight * 6,
              width: EntryWidget.blockWidth * 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: devices.isEmpty
                    ? Colors.white.withOpacity(.5)
                    : Colors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _status,
                style: TextStyle(
                  fontSize: EntryWidget.blockWidth * 3,
                  color: Colors.white,
                ),
              ),
            ),
          )
        ],
      ),
    );
    return MaterialApp(
        home: Scaffold(
      appBar: AppBar(
        title: const Text('USB Serial Plugin example app'),
      ),
      body: Center(
          child: Column(children: <Widget>[
        Text(
            _ports.length > 0
                ? "Available Serial Ports"
                : "No serial devices available",
            style: Theme.of(context).textTheme.headline6),
        ..._ports,
        Text('Status: $_status\n'),
        Text('info: ${_port.toString()}\n'),
        ListTile(
          title: TextField(
            controller: _textController,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Text To Send',
            ),
          ),
          trailing: ElevatedButton(
            child: Text("Send"),
            onPressed: _port == null
                ? null
                : () async {
                    if (_port == null) {
                      return;
                    }
                    String data = _textController.text + "\r\n";
                    await _port!.write(Uint8List.fromList(data.codeUnits));
                    _textController.text = "";
                  },
          ),
        ),
        Text("Result Data", style: Theme.of(context).textTheme.headline6),
        Container(
          height: 250,
          width: double.infinity,
          color: Colors.yellow,
          alignment: Alignment.center,
          child: Center(
            child: ListView.builder(
                controller: _controller,
                itemCount: _serialData.length,
                itemBuilder: ((context, index) {
                  return _serialData[index];
                })),
          ),
        ),

        // InkWell(
        //   onLongPress: () {
        //     streamController.close();
        //     _timer.cancel();
        //     _analogChunks.close();
        //     print("cancelled");
        //   },
        //   onTap: () async {
        //     await openFileAndRead();
        //   },
        //   child: Container(
        //     height: 60,
        //     width: 200,
        //     color: Colors.black,
        //   ),
        // ),

        /////////////////////
        ListView.builder(
          shrinkWrap: true,
          itemCount: preds.length,
          itemBuilder: (context, i) {
            final color = randomColorGen.randomColor(
                colorBrightness: ColorBrightness.light);
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      preds.elementAt(i).label,
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.blueAccent),
                    ),
                  ),
                  Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [
                      PredictionScoreBar(
                        ratio: 1,
                        color: color.withOpacity(0.1),
                      ),
                      PredictionScoreBar(
                        ratio: preds.elementAt(i).score,
                        color: color,
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        ),
      ])),
    ));
  }
}
