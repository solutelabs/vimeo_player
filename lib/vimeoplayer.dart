library vimeoplayer;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock/wakelock.dart';

import 'src/fullscreen_player.dart';
import 'src/quality_links.dart';

///holds the viedo controller details
class ControllerDetails {
  int position;
  bool playingStatus;

  ControllerDetails({this.position, this.playingStatus});
}

// Video player class
class VimeoPlayer extends StatefulWidget {
  final String id;
  final bool autoPlay;
  final bool looping;
  final int position;

  ///[commnecingOverlay] decides whether to show overlay when video player loads video, NOTE - It will function only when autoplay is true
  final bool commencingOverlay;
  final Color fullScreenBackgroundColor;

  ///[overlayTimeOut] in seconds: decide after how much second overlay should vanishes, NOTE - minimum 5 seconds of timeout is stacked
  final int overlayTimeOut;

  final Color loadingIndicatorColor;
  final Color controlsColor;

  final double availableVideoWidth;
  final double availableVideoHeight;

  final Function onVideoCompleted;

  final Function videoPlayListener;
  final Function videoPauseListener;
  final StreamController<void> pauseVideoController;
  final VoidCallback onToggleVideoSize;

  VimeoPlayer({
    @required this.id,
    this.autoPlay = false,
    this.looping,
    this.position,
    this.commencingOverlay = true,
    this.fullScreenBackgroundColor,
    this.loadingIndicatorColor,
    this.controlsColor,
    this.availableVideoWidth,
    this.availableVideoHeight,
    this.onVideoCompleted,
    int overlayTimeOut = 0,
    Key key,
    this.videoPlayListener,
    this.videoPauseListener,
    this.pauseVideoController,
    this.onToggleVideoSize,
  })  : this.overlayTimeOut = max(overlayTimeOut, 5),
        super(key: key);

  @override
  _VimeoPlayerState createState() => _VimeoPlayerState(
      id,
      autoPlay,
      looping,
      position,
      autoPlay ? commencingOverlay : true,
      onVideoCompleted,
      videoPlayListener,
      videoPauseListener);
}

class _VimeoPlayerState extends State<VimeoPlayer> {
  String _id;
  bool autoPlay = false;
  bool looping = false;
  bool _overlay = true;
  bool fullScreen = false;
  int position;
  Function onVideoCompleted;
  Function videoPlayListener;
  Function videoPauseListener;
  StreamSubscription _pauseControllerSubscription;

  _VimeoPlayerState(
      this._id,
      this.autoPlay,
      this.looping,
      this.position,
      this._overlay,
      this.onVideoCompleted,
      this.videoPlayListener,
      this.videoPauseListener)
      : initialOverlay = _overlay;

  //Custom controller
  VideoPlayerController _controller;
  Future<void> initFuture;

  //Quality Class
  QualityLinks _quality;

  //Map _qualityValues;
  var _qualityValue;

  // Seek variable
  bool _seek = false;

  // Video variables
  double videoHeight;
  double videoWidth;
  double videoMargin;

  // Variables for double-tap zones
  double doubleTapRMargin = 36;
  double doubleTapRWidth = 400;
  double doubleTapRHeight = 160;
  double doubleTapLMargin = 10;
  double doubleTapLWidth = 400;
  double doubleTapLHeight = 160;

  //overlay timeout handler
  Timer overlayTimer;

  //indicate if overlay to be display on commencing video or not
  bool initialOverlay;

  //contains the resolution qualities of vimeo video
  List<MapEntry> _qualityValues = [];
  String _currentResolutionQualityKey;

  ///Get Vimeo Specific Video Resoltion Quality in number
  int videoQualityComparer(MapEntry me1, MapEntry me2) {
    final k1 = me1.key as String ?? '';
    final k2 = me2.key as String ?? '';

    const pattern = "[0-9]+(?=p)";

    final exp = RegExp(pattern);
    final q1 = int.tryParse(exp.firstMatch(k1)?.group(0)) ?? 0;
    final q2 = int.tryParse(exp.firstMatch(k2)?.group(0)) ?? 0;

    return q1.compareTo(q2);
  }

  @override
  void initState() {
    //Create class
    _quality = QualityLinks(_id);

    // Initialization of video controllers when receiving data from Vimeo
    _quality.getQualitiesSync().then((value) {
      var qualities = value?.entries?.toList();

      if (qualities != null) {
        qualities.sort(videoQualityComparer);
        qualities = qualities?.reversed?.toList();
        _qualityValues = qualities;
      }

      _currentResolutionQualityKey = value.lastKey();
      _qualityValue = value[_currentResolutionQualityKey];
      _controller = VideoPlayerController.network(_qualityValue);
      _controller.setLooping(looping);
      if (autoPlay) _controller.play();
      initFuture = _controller.initialize();

      // Update application state and redraw
      setState(() {
        SystemChrome.setPreferredOrientations(
            [DeviceOrientation.portraitDown, DeviceOrientation.portraitUp]);
      });

      /*
      * Video End Callback
      * */
      _controller.addListener(() {
        if (_controller.value.position == _controller.value.duration) {
          widget.onVideoCompleted.call();
        }

        if (_controller.value.isPlaying) {
          widget.videoPlayListener.call();
        } else {
          widget.videoPauseListener.call();
        }
      });
    });

    // Video page takes precedence over portrait orientation
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitDown, DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);

    //Keep screen active till video plays
    Wakelock.enable();

    _pauseControllerSubscription = widget.pauseVideoController?.stream?.listen(
      (_) => _controller.pause(),
    );

    super.initState();
  }

  ///display or vanishes the overlay i.e playing controls, etc.
  void _toogleOverlay() {
    //Inorder to avoid descrepancy in overlay popping up & vanishing out
    overlayTimer?.cancel();
    if (!_overlay) {
      overlayTimer = Timer(Duration(seconds: widget.overlayTimeOut), () {
        setState(() {
          _overlay = false;
          doubleTapRHeight = videoHeight + 36;
          doubleTapLHeight = videoHeight + 16;
          doubleTapRMargin = 0;
          doubleTapLMargin = 0;
        });
      });
    }
    // Edit the size of the double tap area when showing the overlay.
    // Made to open the "Full Screen" and "Quality" buttons
    setState(() {
      _overlay = !_overlay;
      if (_overlay) {
        doubleTapRHeight = videoHeight - 36;
        doubleTapLHeight = videoHeight - 10;
        doubleTapRMargin = 36;
        doubleTapLMargin = 10;
      } else if (!_overlay) {
        doubleTapRHeight = videoHeight + 36;
        doubleTapLHeight = videoHeight + 16;
        doubleTapRMargin = 0;
        doubleTapLMargin = 0;
      }
    });
  }

  // Draw the player elements
  @override
  Widget build(BuildContext context) {
    videoWidth = MediaQuery.of(context).size.width;

    return Center(
      child: Stack(
        alignment: AlignmentDirectional.center,
        children: <Widget>[
          GestureDetector(
            child: FutureBuilder(
                future: initFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    //Управление шириной и высотой видео
                    double delta = MediaQuery.of(context).size.width -
                        MediaQuery.of(context).size.height *
                            _controller.value.aspectRatio;
                    //Рассчет ширины и высоты видео плеера относительно сторон
                    // и ориентации устройства
                    if (MediaQuery.of(context).orientation ==
                            Orientation.portrait ||
                        delta < 0) {
                      videoHeight = MediaQuery.of(context).size.width /
                          _controller.value.aspectRatio;
                      double diff = widget.availableVideoHeight - videoHeight;
                      if (diff < 0.0) {
                        // In this case adjust videoMargin
                        videoHeight = widget.availableVideoHeight;
                        videoWidth =
                            videoHeight * _controller.value.aspectRatio;
                        videoMargin = 0;
                      } else {
                        videoMargin = 0;
                      }
                    } else {
                      videoHeight = MediaQuery.of(context).size.height;
                      videoWidth = videoHeight * _controller.value.aspectRatio;
                      videoMargin =
                          (MediaQuery.of(context).size.width - videoWidth) / 2;
                    }

                    //Начинаем с того же места, где и остановились при смене качества
                    if (_seek && _controller.value.duration.inSeconds > 2) {
                      _controller.seekTo(Duration(seconds: position));
                      _seek = false;
                    }

                    //Отрисовка элементов плеера
                    return Stack(
                      children: <Widget>[
                        Center(
                          child: Container(
                            height: videoHeight,
                            width: videoWidth,
                            color: Colors.black54,
                            margin: EdgeInsets.only(
                                left: videoMargin, right: videoMargin),
                            child: VideoPlayer(_controller),
                          ),
                        ),
                        _videoOverlay(),
                      ],
                    );
                  } else {
                    return Center(
                        heightFactor: 6,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFF22A3D2)),
                        ));
                  }
                }),
            onTap: () {
              //Редактируем размер области дабл тапа при показе оверлея.
              // Сделано для открытия кнопок "Во весь экран" и "Качество"
              setState(() {
                _overlay = !_overlay;
                if (_overlay) {
                  doubleTapRHeight = videoHeight - 36;
                  doubleTapLHeight = videoHeight - 10;
                  doubleTapRMargin = 36;
                  doubleTapLMargin = 10;
                } else if (!_overlay) {
                  doubleTapRHeight = videoHeight + 36;
                  doubleTapLHeight = videoHeight + 16;
                  doubleTapRMargin = 0;
                  doubleTapLMargin = 0;
                }
              });
            },
          ),
          Container(
            width: videoWidth,
            height: videoWidth * 0.3,
            child: Row(
              children: [
                InkWell(
                    //======= Перемотка назад =======//
                    child: Container(
                      width: videoWidth * 0.3,
                      height: doubleTapLHeight,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(),
                    ),
                    enableFeedback: true,
                    splashColor: Colors.white12,
                    // Изменение размера блоков дабл тапа. Нужно для открытия кнопок
                    // "Во весь экран" и "Качество" при включенном overlay
                    onTap: () {
                      setState(() {
                        _overlay = !_overlay;
                        if (_overlay) {
                          doubleTapRHeight = videoHeight - 36;
                          doubleTapLHeight = videoHeight - 10;
                          doubleTapRMargin = 36;
                          doubleTapLMargin = 10;
                        } else if (!_overlay) {
                          doubleTapRHeight = videoHeight + 36;
                          doubleTapLHeight = videoHeight + 16;
                          doubleTapRMargin = 0;
                          doubleTapLMargin = 0;
                        }
                      });
                    },
                    onDoubleTap: () {
                      setState(() {
                        _controller.seekTo(Duration(
                            seconds:
                                _controller.value.position.inSeconds - 10));
                      });
                    }),
                Spacer(flex: 1),
                InkWell(
                    enableFeedback: true,
                    splashColor: Colors.white12,
                    child: Container(
                      //======= Перемотка вперед =======//
                      width: videoWidth * 0.3,
                      height: videoHeight,
                      decoration: BoxDecoration(),
                    ),
                    // Изменение размера блоков дабл тапа. Нужно для открытия кнопок
                    // "Во весь экран" и "Качество" при включенном overlay
                    onTap: () {
                      setState(() {
                        _overlay = !_overlay;
                        if (_overlay) {
                          doubleTapRHeight = videoHeight - 36;
                          doubleTapLHeight = videoHeight - 10;
                          doubleTapRMargin = 36;
                          doubleTapLMargin = 10;
                        } else if (!_overlay) {
                          doubleTapRHeight = videoHeight + 36;
                          doubleTapLHeight = videoHeight + 16;
                          doubleTapRMargin = 0;
                          doubleTapLMargin = 0;
                        }
                      });
                    },
                    onDoubleTap: () {
                      setState(() {
                        _controller.seekTo(Duration(
                            seconds:
                                _controller.value.position.inSeconds + 10));
                      });
                    }),
              ],
            ),
          )
        ],
      ),
    );
  }

  //================================ Quality ================================//
  void _settingModalBottomSheet(context) {
    showModalBottomSheet(
        context: context,
        builder: (BuildContext bc) {
          // Forming the quality list
          final children = <Widget>[];
          _qualityValues.forEach((quality) => (children.add(new ListTile(
              title: new Text(" ${quality.key.toString()} fps"),
              trailing: _currentResolutionQualityKey == quality.key
                  ? Icon(Icons.check)
                  : null,
              onTap: () => {
                    // Update application state and redraw
                    setState(() {
                      _controller.pause();
                      _currentResolutionQualityKey = quality.key;
                      _qualityValue = quality.value;
                      _controller =
                          VideoPlayerController.network(_qualityValue);
                      _controller.setLooping(looping);
                      _seek = true;
                      initFuture = _controller.initialize();
                      _controller.play();
                      Navigator.pop(context); //close sheet
                    }),
                  }))));
          // Output quality items as a list
          return Container(
            child: Wrap(
              children: children,
            ),
          );
        });
  }

  //================================ OVERLAY ================================//
  Widget _videoOverlay() {
    return _overlay
        ? Stack(
            children: <Widget>[
              GestureDetector(
                child: Center(
                  child: Container(
                    width: videoWidth,
                    height: videoHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          const Color(0x662F2C47),
                          const Color(0x662F2C47)
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: IconButton(
                    padding: EdgeInsets.only(
                      top: videoHeight / 2 - 50,
                      bottom: videoHeight / 2 - 30,
                    ),
                    icon:
                        _controller.value.position == _controller.value.duration
                            ? Icon(
                                Icons.replay,
                                color: widget.controlsColor,
                                size: 60.0,
                              )
                            : _controller.value.isPlaying
                                ? Icon(Icons.pause,
                                    size: 60.0, color: widget.controlsColor)
                                : Icon(Icons.play_arrow,
                                    size: 60.0, color: widget.controlsColor),
                    onPressed: () {
                      setState(() {
                        //replay video
                        if (_controller.value.position ==
                            _controller.value.duration) {
                          setState(() {
                            _controller.seekTo(Duration());
                            _controller.play();
                          });
                        }
                        //vanish the overlay if play button is pressed
                        else if (!_controller.value.isPlaying) {
                          overlayTimer?.cancel();
                          _controller.play();
                          _overlay = !_overlay;
                        } else {
                          _controller.pause();
                        }
                      });
                    }),
              ),
              //),
              Container(
                alignment: Alignment.bottomRight,
                width: MediaQuery.of(context).size.width,
                margin: const EdgeInsets.symmetric(horizontal: 8.0),
                child: IconButton(
                    alignment: AlignmentDirectional.center,
                    icon: Icon(Icons.fullscreen, size: 30.0),
                    onPressed: () async {
                      widget.onToggleVideoSize?.call();
                      return;
                      /*
                      final playing = _controller.value.isPlaying;
                      setState(() {
                        _controller.pause();
                        overlayTimer?.cancel();
                      });
                      // Create a new page with a full screen player,
                      // transfer data to the player and return the position when
                      // return back. Until we returned from
                      // fullscreen - the program is pending
                      position = await Navigator.push(
                          context,
                          PageRouteBuilder(
                              opaque: false,
                              pageBuilder: (BuildContext context, _, __) =>
                                  FullscreenPlayer(
                                      id: _id,
                                      autoPlay: true,
                                      controller: _controller,
                                      position:
                                          _controller.value.position.inSeconds,
                                      initFuture: initFuture,
                                      qualityValue: _qualityValue),
                              transitionsBuilder: (___,
                                  Animation<double> animation,
                                  ____,
                                  Widget child) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                      scale: animation, child: child),
                                );
                              }));
                      setState(() {
                        _controller.play();
                        _seek = true;
                      });
                      */
                    }),
              ),
              Container(
                alignment: Alignment.topRight,
                width: MediaQuery.of(context).size.width,
                margin: const EdgeInsets.symmetric(horizontal: 8.0),
                child: IconButton(
                    icon: Icon(Icons.settings, size: 26.0),
                    onPressed: () {
                      position = _controller.value.position.inSeconds;
                      _seek = true;
                      _settingModalBottomSheet(context);
                      setState(() {});
                    }),
              ),
              Container(
                // ===== Slider ===== //
                width: MediaQuery.of(context).size.width,
                margin: EdgeInsets.only(top: videoHeight - 70),
                //CHECK IT
                child: Container(
                    width: videoWidth,
                    alignment: Alignment.center,
                    child: _videoOverlaySlider()),
              )
            ],
          )
        : Center(
            child: Container(
              height: 5,
              width: videoWidth,
              margin: EdgeInsets.only(top: videoHeight - 5),
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Color(0xFF22A3D2),
                  backgroundColor: Color(0x5515162B),
                  bufferedColor: Color(0x5583D8F7),
                ),
                padding: EdgeInsets.only(top: 2),
              ),
            ),
          );
  }

  // ==================== SLIDER =================== //
  Widget _videoOverlaySlider() {
    return ValueListenableBuilder(
      valueListenable: _controller,
      builder: (context, VideoPlayerValue value, child) {
        if (!value.hasError && value.initialized) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 46,
                alignment: Alignment(0, 0),
                child: Text(
                  '${_twoDigits(value.position.inMinutes)}:${_twoDigits(value.position.inSeconds - value.position.inMinutes * 60)}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Container(
                height: 20,
                width: videoWidth - 92,
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: Color(0xFF22A3D2),
                    backgroundColor: Color(0x5515162B),
                    bufferedColor: Color(0x5583D8F7),
                  ),
                  padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
                ),
              ),
              Container(
                width: 46,
                alignment: Alignment(0, 0),
                child: Text(
                  '${_twoDigits(value.duration.inMinutes)}:${_twoDigits(value.duration.inSeconds - value.duration.inMinutes * 60)}',
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        } else {
          Wakelock
              .disable(); //Now screen can be inactive as per system defined configurations
          return Container();
        }
      },
    );
  }

  ///Convert the integer number in atleast 2 digit format (i.e appending 0 in front if any)
  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  void dispose() {
    overlayTimer?.cancel();
    _controller.dispose();
    _pauseControllerSubscription?.cancel();
    Wakelock.disable();
    super.dispose();
  }
}
