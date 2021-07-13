// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:html' hide Document, Console;
import 'dart:math' as math;

import 'package:dart_pad/elements/material_tab_controller.dart';
import 'package:dart_pad/src/ga.dart';
import 'package:dart_pad/util/detect_flutter.dart';
import 'package:mdc_web/mdc_web.dart';
import 'package:pedantic/pedantic.dart';
import 'package:split/split.dart';

import 'check_localstorage.dart';
import 'completion.dart';
import 'context.dart';
import 'core/dependencies.dart';
import 'core/modules.dart';
import 'dart_pad.dart';
import 'editing/codemirror_options.dart';
import 'editing/editor_codemirror.dart';
import 'elements/analysis_results_controller.dart';
import 'elements/button.dart';
import 'elements/console.dart';
import 'elements/counter.dart';
import 'elements/dialog.dart';
import 'elements/elements.dart';
import 'modules/dart_pad_module.dart';
import 'modules/dartservices_module.dart';
import 'services/common.dart';
import 'services/dartservices.dart';
import 'services/execution_iframe.dart';
import 'sharing/editor_ui.dart';
import 'sharing/gists.dart';
import 'util/query_params.dart' show queryParams;

const int defaultSplitterWidth = 6;

Embed? get embed => _embed;

Embed? _embed;

void init(EmbedOptions options) {
  _embed = Embed(options);
}

// ignore: constant_identifier_names
enum EmbedMode { dart, flutter, html, inline, flutter_showcase }

class EmbedOptions {
  final EmbedMode mode;

  const EmbedOptions(this.mode);
}

/// An embeddable DartPad UI that provides the ability to test the user's code
/// snippet against a desired result.
class Embed extends EditorUi {
  final EmbedOptions options;

  var _executionButtonCount = 0;
  late final MDCButton reloadGistButton;
  late final MDCButton installButton;
  late final MDCButton formatButton;
  late final MDCButton showHintButton;
  late final MDCButton copyCodeButton;
  late final MDCButton openInDartPadButton;
  late final MDCButton menuButton;

  MDCButton? editorCodeInputTabButton;

  late final DElement navBarElement;
  late final EmbedTabController tabController;
  late final TabView editorTabView;
  late final TabView testTabView;
  late final TabView solutionTabView;
  late final TabView htmlTabView;
  late final TabView cssTabView;
  late final DElement solutionTab;
  late final MDCMenu menu;

  late final DElement showTestCodeCheckmark;
  late final DElement editableTestSolutionCheckmark;
  bool _editableTestSolution = false;
  bool _showTestCode = false;

  late final DElement nullSafetyCheckmark;
  bool _nullSafetyEnabled = false;

  late final Counter unreadConsoleCounter;

  late final FlashBox testResultBox;
  late final FlashBox hintBox;

  final CodeMirrorFactory editorFactory = codeMirrorFactory;

  late final Editor userCodeEditor;
  late final Editor testEditor;
  late final Editor solutionEditor;
  Editor? htmlEditor;
  Editor? cssEditor;

  @override
  late final EmbedContext context;

  late final Splitter splitter;

  late final Console consoleExpandController;
  late final DElement webOutputLabel;
  late final DElement featureMessage;

  late final MDCLinearProgress linearProgress;
  Map<String, String> lastInjectedSourceCode = <String, String>{};

  bool _editorIsBusy = true;

  bool get editorIsBusy => _editorIsBusy;

  @override
  Editor get editor => userCodeEditor;

  @override
  Document get currentDocument => userCodeEditor.document;

  /// Toggles the state of several UI components based on whether the editor is
  /// too busy to handle code changes, execute/reset requests, etc.
  set editorIsBusy(bool value) {
    _editorIsBusy = value;
    if (value) {
      linearProgress.root.classes.remove('hide');
    } else {
      linearProgress.root.classes.add('hide');
    }
    userCodeEditor.readOnly = value;
    runButton.disabled = value;
    formatButton.disabled = value;
    reloadGistButton.disabled = value;
    showHintButton.disabled = value;
    copyCodeButton.disabled = value;
  }

  Embed(this.options) {
    _initHostListener();

    if (!checkLocalStorage()) {
      dialog.showOk(
          'Missing browser features',
          'DartPad requires localStorage to be enabled. '
              'For more information, visit '
              '<a href="https://dart.dev/tools/dartpad/troubleshoot" '
              'target="_parent">dart.dev/tools/dartpad/troubleshoot</a>.');
    }

    tabController =
        EmbedTabController(MDCTabBar(querySelector('.mdc-tab-bar')!), dialog);

    var tabNames = ['editor', 'solution', 'test'];
    if (options.mode == EmbedMode.html) {
      tabNames = ['editor', 'html', 'css', 'solution', 'test'];
    }

    for (var name in tabNames) {
      tabController.registerTab(
        TabElement(querySelector('#$name-tab')!, name: name, onSelect: () {
          editorTabView.setSelected(name == 'editor');
          testTabView.setSelected(name == 'test');
          solutionTabView.setSelected(name == 'solution');
          htmlTabView.setSelected(name == 'html');
          cssTabView.setSelected(name == 'css');

          if (name == 'editor') {
            userCodeEditor.resize();
            userCodeEditor.focus();
          } else if (name == 'test') {
            testEditor.resize();
            testEditor.focus();
          } else if (name == 'solution') {
            solutionEditor.resize();
            solutionEditor.focus();
          } else if (name == 'html') {
            htmlEditor!.resize();
            htmlEditor!.focus();
          } else if (name == 'css') {
            cssEditor!.resize();
            cssEditor!.focus();
          }
        }),
      );
    }

    solutionTab = DElement(querySelector('#solution-tab')!);

    navBarElement = DElement(querySelector('#navbar')!);

    unreadConsoleCounter =
        Counter(querySelector('#unread-console-counter') as SpanElement);

    runButton = MDCButton(querySelector('#execute') as ButtonElement)
      ..onClick.listen((_) => handleRun());

    // Flutter showcase mode
    var editorCodeInputTabButtonElement =
        querySelector('#editor-panel-show-code-button');
    if (editorCodeInputTabButtonElement != null) {
      editorCodeInputTabButton = MDCButton(
          querySelector('#editor-panel-show-code-button') as ButtonElement)
        ..onClick.listen(
          (_) => _toggleCodeInput(),
        );
    }

    reloadGistButton = MDCButton(querySelector('#reload-gist') as ButtonElement)
      ..onClick.listen((_) {
        if (gistId!.isNotEmpty || sampleId.isNotEmpty || githubParamsPresent) {
          _loadAndShowGist();
        } else {
          _resetCode();
        }
      });

    copyCodeButton =
        MDCButton(querySelector('#copy-code') as ButtonElement, isIcon: true)
          ..onClick.listen((_) => _handleCopyCode());
    openInDartPadButton = MDCButton(
        querySelector('#open-in-dartpad') as ButtonElement,
        isIcon: true)
      ..onClick.listen((_) => _handleOpenInDartPad());

    showHintButton = MDCButton(querySelector('#show-hint') as ButtonElement)
      ..onClick.listen((_) {
        var hintElement = DivElement()..text = context.hint;
        var showSolutionButton = AnchorElement()
          ..style.cursor = 'pointer'
          ..text = 'Show solution';
        showSolutionButton.onClick.listen((_) {
          tabController.selectTab('solution', force: true);
        });
        hintBox.showElements([hintElement, showSolutionButton]);
        ga.sendEvent('view', 'hint');
      })
      ..element.hidden = true;

    tabController.setTabVisibility('test', false);
    showTestCodeCheckmark = DElement(querySelector('#show-test-checkmark')!);
    editableTestSolutionCheckmark =
        DElement(querySelector('#editable-test-solution-checkmark')!);
    nullSafetyCheckmark =
        DElement(querySelector('#toggle-null-safety-checkmark')!);

    menuButton =
        MDCButton(querySelector('#menu-button') as ButtonElement, isIcon: true)
          ..onClick.listen((_) {
            menu.open = !menu.open!;
          });
    menu = MDCMenu(querySelector('#main-menu'))
      ..setAnchorCorner(AnchorCorner.bottomLeft)
      ..setAnchorElement(menuButton.element);
    menu.listen('MDCMenu:selected', (e) {
      final selectedIndex = (e as CustomEvent).detail['index'] as int?;
      switch (selectedIndex) {
        case 0:
          // Show test code
          _showTestCode = !_showTestCode;
          showTestCodeCheckmark.toggleClass('hide', !_showTestCode);
          tabController.setTabVisibility('test', _showTestCode);
          break;
        case 1:
          // Editable test/solution
          _editableTestSolution = !_editableTestSolution;
          editableTestSolutionCheckmark.toggleClass(
              'hide', !_editableTestSolution);
          testEditor.readOnly =
              solutionEditor.readOnly = !_editableTestSolution;
          break;
        case 2:
          // Null safety
          nullSafetyEnabled = !nullSafetyEnabled;
          break;
      }
    });

    formatButton = MDCButton(querySelector('#format-code') as ButtonElement)
      ..onClick.listen(
        (_) => _format(),
      );
    installButton = MDCButton(querySelector('#install-button') as ButtonElement)
      ..onClick.listen(
        (_) => _showInstallPage(),
      );

    testResultBox = FlashBox(querySelector('#test-result-box') as DivElement);
    hintBox = FlashBox(querySelector('#hint-box') as DivElement);
    var editorTheme = isDarkMode ? 'darkpad' : 'dartpad';

    userCodeEditor = editorFactory.createFromElement(
        querySelector('#user-code-editor')!,
        options: codeMirrorOptions)
      ..theme = editorTheme
      ..mode = 'dart'
      ..showLineNumbers = true;
    userCodeEditor.autoCloseBrackets = false;

    testEditor = editorFactory.createFromElement(querySelector('#test-editor')!,
        options: codeMirrorOptions)
      ..theme = editorTheme
      ..mode = 'dart'
      ..readOnly = !_editableTestSolution
      ..showLineNumbers = true;

    solutionEditor = editorFactory.createFromElement(
        querySelector('#solution-editor')!,
        options: codeMirrorOptions)
      ..theme = editorTheme
      ..mode = 'dart'
      ..readOnly = !_editableTestSolution
      ..showLineNumbers = true;

    final htmlEditorElement = querySelector('#html-editor');
    if (htmlEditorElement != null) {
      htmlEditor = editorFactory.createFromElement(htmlEditorElement,
          options: codeMirrorOptions)
        ..theme = editorTheme
        // TODO(ryjohn): why doesn't editorFactory.modes have html?
        ..mode = 'xml'
        ..showLineNumbers = true;
    }

    final cssEditorElement = querySelector('#css-editor');
    if (cssEditorElement != null) {
      cssEditor = editorFactory.createFromElement(cssEditorElement,
          options: codeMirrorOptions)
        ..theme = editorTheme
        ..mode = 'css'
        ..showLineNumbers = true;
    }

    if (!showInstallButton) {
      querySelector('#install-button')!.setAttribute('hidden', '');
    }

    var editorTabViewElement = querySelector('#user-code-view');
    if (editorTabViewElement != null) {
      editorTabView = TabView(DElement(editorTabViewElement));
    }

    var testTabViewElement = querySelector('#test-view');
    if (testTabViewElement != null) {
      testTabView = TabView(DElement(testTabViewElement));
    }

    var solutionTabViewElement = querySelector('#solution-view');
    if (solutionTabViewElement != null) {
      solutionTabView = TabView(DElement(solutionTabViewElement));
    }

    var htmlTabViewElement = querySelector('#html-view');
    if (htmlTabViewElement != null) {
      htmlTabView = TabView(DElement(htmlTabViewElement));
    }

    var cssTabViewElement = querySelector('#css-view');
    if (cssTabViewElement != null) {
      cssTabView = TabView(DElement(querySelector('#css-view')!));
    }

    executionService =
        ExecutionServiceIFrame(querySelector('#frame') as IFrameElement)
          ..frameSrc = isDarkMode
              ? '../scripts/frame_dark.html'
              : '../scripts/frame.html';

    executionService.onStderr.listen((err) {
      consoleExpandController.showOutput(err, error: true);
    });

    executionService.onStdout.listen((msg) {
      consoleExpandController.showOutput(msg);
    });

    executionService.testResults.listen((result) {
      if (result.messages.isEmpty) {
        result.messages
            .add(result.success ? 'All tests passed!' : 'Test failed.');
      }
      testResultBox.showStrings(
        result.messages,
        result.success ? FlashBoxStyle.success : FlashBoxStyle.warn,
      );
      ga.sendEvent(
          'execution', (result.success) ? 'test-success' : 'test-failure');
    });

    analysisResultsController = AnalysisResultsController(
        DElement(querySelector('#issues')!),
        DElement(querySelector('#issues-message')!),
        DElement(querySelector('#issues-toggle')!))
      ..onItemClicked.listen((item) {
        _jumpTo(item.line, item.charStart, item.charLength, focus: true);
      });

    if (options.mode == EmbedMode.flutter ||
        options.mode == EmbedMode.html ||
        options.mode == EmbedMode.flutter_showcase) {
      var controller = ConsoleExpandController(
          expandButton: querySelector('#console-output-header')!,
          footer: querySelector('#console-output-footer')!,
          expandIcon: querySelector('#console-expand-icon')!,
          unreadCounter: unreadConsoleCounter,
          consoleElement: querySelector('#console-output-container')!,
          editorUi: this,
          onSizeChanged: () {
            userCodeEditor.resize();
            testEditor.resize();
            solutionEditor.resize();
            htmlEditor?.resize();
            cssEditor?.resize();
          });
      consoleExpandController = controller;
      if (shouldOpenConsole) {
        controller.open();
      }
    } else {
      consoleExpandController =
          Console(DElement(querySelector('#console-output-container')!));
    }

    var webOutputLabelElement = querySelector('#web-output-label');
    if (webOutputLabelElement != null) {
      webOutputLabel = DElement(webOutputLabelElement);
    }

    featureMessage = DElement(querySelector('#feature-message')!);
    featureMessage.toggleAttr('hidden', true);

    linearProgress = MDCLinearProgress(querySelector('#progress-bar')!);
    linearProgress.determinate = false;

    _initBusyLights();

    _initModules()
        .then((_) => _init())
        .then((_) => _emitReady())
        .then((_) => _initNullSafety());
  }

  /// Initializes a listener for messages from the parent window. Allows this
  /// embedded iframe to display and run arbitrary Dart code.
  void _initHostListener() {
    window.addEventListener('message', (dynamic event) {
      var data = event.data;
      if (data is! Map) {
        // Ignore unexpected messages
        return;
      }

      var type = data['type'];

      if (type == 'sourceCode') {
        lastInjectedSourceCode =
            Map<String, String>.from(data['sourceCode'] as Map);
        _resetCode();

        if (autoRunEnabled) {
          handleRun();
        }
      }
    });
  }

  /// Sends a ready message to the parent page
  void _emitReady() {
    window.parent!.postMessage({'sender': 'frame', 'type': 'ready'}, '*');
  }

  // Option for the GitHub gist ID that should be loaded into the editors.
  String? get gistId {
    final id = queryParams.gistId;
    return isLegalGistId(id) ? id : '';
  }

  // Option for Light / Dark theme (defaults to light)
  bool get isDarkMode {
    return queryParams.theme == 'dark';
  }

  // Option to run the snippet immediately (defaults to  false)
  bool get autoRunEnabled {
    return queryParams.autoRunEnabled;
  }

  bool get shouldOpenConsole {
    return queryParams.shouldOpenConsole;
  }

  // Whether or not to show the Install button. (defaults to true)
  bool get showInstallButton {
    if (queryParams.hasShowInstallButton) {
      return queryParams.showInstallButton;
    }

    // Default to true
    return true;
  }

  // ID of an API Doc sample that should be loaded into the editors.
  String get sampleId => queryParams.sampleId ?? '';

  // An optional channel indicating which version of the API Docs to use when
  // loading a sample. Defaults to the stable channel.
  FlutterSdkChannel get sampleChannel {
    final channelStr = queryParams.sampleChannel?.toLowerCase();

    if (channelStr == 'master') {
      return FlutterSdkChannel.master;
    } else if (channelStr == 'dev') {
      return FlutterSdkChannel.dev;
    } else if (channelStr == 'beta') {
      return FlutterSdkChannel.beta;
    } else {
      return FlutterSdkChannel.stable;
    }
  }

  // GitHub params for loading an exercise from a repo. The first three are
  // required to load something, while the fourth, gh_ref, is an optional branch
  // name or commit SHA.
  String get githubOwner => queryParams.githubOwner ?? '';

  String get githubRepo => queryParams.githubRepo ?? '';

  String get githubPath => queryParams.githubPath ?? '';

  String? get githubRef => queryParams.githubRef;

  bool get githubParamsPresent =>
      githubOwner.isNotEmpty && githubRepo.isNotEmpty && githubPath.isNotEmpty;

  void _initNullSafety() {
    if (queryParams.hasNullSafety && queryParams.nullSafety) {
      nullSafetyEnabled = true;
    }
  }

  @override
  set nullSafetyEnabled(bool enabled) {
    _nullSafetyEnabled = enabled;
    _handleNullSafetySwitched(enabled);
    featureMessage.text = 'Null safety';
    featureMessage.toggleAttr('hidden', !enabled);
    nullSafetyCheckmark.toggleClass('hide', !enabled);
  }

  @override
  bool get nullSafetyEnabled {
    return _nullSafetyEnabled;
  }

  void _handleNullSafetySwitched(bool enabled) {
    var api = deps[DartservicesApi] as DartservicesApi?;
    if (enabled) {
      api!.rootUrl = nullSafetyServerUrl;
      window.localStorage['null_safety'] = 'true';
    } else {
      api!.rootUrl = preNullSafetyServerUrl;
      window.localStorage['null_safety'] = 'false';
    }
    unawaited(performAnalysis());
  }

  Future<void> _initModules() async {
    var modules = ModuleManager();

    modules.register(DartPadModule());
    modules.register(DartServicesModule());

    await modules.start();
  }

  void _initBusyLights() {
    busyLight = DBusyLight(querySelector('#dartbusy')!);
  }

  void _init() {
    deps[GistLoader] = GistLoader.defaultFilters();
    deps[Analytics] = Analytics();

    context = EmbedContext(
        userCodeEditor, testEditor, solutionEditor, htmlEditor, cssEditor);

    editorFactory.registerCompleter(
        'dart', DartCompleter(dartServices, userCodeEditor.document));

    context.onDartDirty.listen((_) => busyLight.on());
    context.onDartReconcile.listen((_) => performAnalysis());

    initKeyBindings();

    var horizontal = true;
    var webOutput = querySelector('#web-output')!;
    List<Element> splitterElements;
    if (options.mode == EmbedMode.flutter || options.mode == EmbedMode.html) {
      var editorAndConsoleContainer =
          querySelector('#editor-and-console-container')!;
      splitterElements = [editorAndConsoleContainer, webOutput];
    } else if (options.mode == EmbedMode.inline) {
      var editorContainer = querySelector('#editor-container')!;
      var consoleView = querySelector('#console-view')!;
      consoleView.removeAttribute('hidden');
      splitterElements = [editorContainer, consoleView];
      horizontal = false;
    } else if (options.mode == EmbedMode.flutter_showcase) {
      // do not split elements in flutter_showcase mode
      splitterElements = <Element>[];
    } else {
      var editorContainer = querySelector('#editor-container')!;
      var consoleView = querySelector('#console-view')!;
      consoleView.removeAttribute('hidden');
      splitterElements = [editorContainer, consoleView];
    }

    // Flutter showcase mode does not show code input by default
    if (options.mode == EmbedMode.flutter_showcase) {
      _updateShowcase();
    } else {
      splitter = flexSplit(
        splitterElements,
        horizontal: horizontal,
        gutterSize: defaultSplitterWidth,
        // set initial sizes (in percentages)
        sizes: [initialSplitPercent, (100 - initialSplitPercent)],
        // set the minimum sizes (in pixels)
        minSize: [100, 100],
      );
      listenForResize(splitterElements[0]);
    }

    if (gistId!.isNotEmpty || sampleId.isNotEmpty || githubParamsPresent) {
      _loadAndShowGist(analyze: false);
    }

    if (gistId!.isEmpty) {
      openInDartPadButton.toggleAttr('hidden', true);
    }

    // set enabled/disabled state of various buttons
    editorIsBusy = false;
  }

  @override
  void initKeyBindings() {
    keys.bind(['ctrl-space', 'macctrl-space'], () {
      if (userCodeEditor.hasFocus) {
        userCodeEditor.showCompletions();
      }
    }, 'Completion');

    keys.bind(['alt-enter'], () {
      userCodeEditor.showCompletions(onlyShowFixes: true);
    }, 'Quick fix');

    keys.bind(['shift-ctrl-f', 'shift-macctrl-f'], () {
      _format();
    }, 'Format');

    document.onKeyUp.listen(_handleAutoCompletion);
    super.initKeyBindings();
  }

  Future<void> _loadAndShowGist({bool analyze = true}) async {
    if (gistId!.isEmpty && sampleId.isEmpty && !githubParamsPresent) {
      print('Cannot load gist: neither id, sample_id, nor GitHub repo info is '
          'present.');
      return;
    }

    editorIsBusy = true;

    final loader = deps[GistLoader] as GistLoader?;

    try {
      Gist gist;

      if (gistId!.isNotEmpty) {
        gist = await loader!.loadGist(gistId);
      } else if (sampleId.isNotEmpty) {
        // Right now, there are only two hosted versions of the docs: master and
        // stable. Default to stable for dev and beta.
        final channel = (sampleChannel == FlutterSdkChannel.master)
            ? FlutterSdkChannel.master
            : FlutterSdkChannel.stable;
        gist = await loader!.loadGistFromAPIDocs(sampleId, channel);
      } else {
        gist = await loader!.loadGistFromRepo(
          owner: githubOwner,
          repo: githubRepo,
          path: githubPath,
          ref: githubRef,
        );
      }

      setContextSources(<String, String>{
        'main.dart': gist.getFile('main.dart')?.content ?? '',
        'index.html': gist.getFile('index.html')?.content ?? '',
        'styles.css': gist.getFile('styles.css')?.content ?? '',
        'solution.dart': gist.getFile('solution.dart')?.content ?? '',
        'test.dart': gist.getFile('test.dart')?.content ?? '',
        'hint.txt': gist.getFile('hint.txt')?.content ?? '',
      });

      if (analyze) {
        unawaited(performAnalysis());
      }

      if (autoRunEnabled) {
        unawaited(handleRun());
      }
    } on GistLoaderException catch (ex) {
      // No gist was loaded, so clear the editors.
      setContextSources(<String, String>{});

      if (ex.failureType == GistLoaderFailureType.contentNotFound) {
        await dialog.showOk(
            'Error loading gist',
            'No gist was found for the gist ID, sample ID, or repository '
                'information provided.');
      } else if (ex.failureType == GistLoaderFailureType.rateLimitExceeded) {
        await dialog.showOk(
            'Error loading files',
            'GitHub\'s rate limit for '
                'API requests has been exceeded. This is typically caused by '
                'repeatedly loading a single page that has many DartPad embeds or '
                'when many users are accessing DartPad (and therefore GitHub\'s '
                'API server) from a single, shared IP address. Quotas are '
                'typically renewed within an hour, so the best course of action is '
                'to try back later.');
      } else if (ex.failureType ==
          GistLoaderFailureType.invalidExerciseMetadata) {
        if (ex.message != null) {
          print(ex.message);
        }
        await dialog.showOk(
            'Error loading files',
            'DartPad could not load the requested exercise. Either one of the '
                'required files wasn\'t available, or the exercise metadata was '
                'invalid.');
      } else {
        await dialog.showOk('Error loading files',
            'An error occurred while the requested files.');
      }
    }
  }

  void _resetCode() {
    setContextSources(lastInjectedSourceCode);
    Timer.run(() => unawaited(performAnalysis()));
  }

  void _handleCopyCode() {
    var textElement = document.createElement('textarea') as TextAreaElement;
    textElement.value = _getActiveSourceCode();
    document.body!.append(textElement);
    textElement.select();
    document.execCommand('copy');
    textElement.remove();
  }

  void _handleOpenInDartPad() {
    window.open('/embed-$_modeName.html?id=$gistId', 'DartPad_$gistId');
  }

  /// Returns the name of the current embed mode
  /// (html, flutter, inline, dart, flutter_showcase).
  String get _modeName {
    return options.mode.toString().split('.').last;
  }

  String _getActiveSourceCode() {
    String activeSource;
    var activeTabName = tabController.selectedTab.name;

    switch (activeTabName) {
      case 'editor':
        activeSource = context.dartSource;
        break;
      case 'css':
        activeSource = context.cssSource;
        break;
      case 'html':
        activeSource = context.htmlSource;
        break;
      case 'solution':
        activeSource = context.solution;
        break;
      case 'test':
        activeSource = context.testMethod;
        break;
      default:
        activeSource = context.dartSource;
        break;
    }

    return activeSource;
  }

  void setContextSources(Map<String, String> sources) {
    context.dartSource = sources['main.dart'] ?? '';
    context.solution = sources['solution.dart'] ?? '';
    context.testMethod = sources['test.dart'] ?? '';
    context.htmlSource = sources['index.html'] ?? '';
    context.cssSource = sources['styles.css'] ?? '';
    context.hint = sources['hint.txt'] ?? '';
    if (sources.containsKey('ga_id')) {
      _sendVirtualPageView(sources['ga_id']);
    }
    tabController.setTabVisibility(
        'test', context.testMethod.isNotEmpty && _showTestCode);
    menuButton.toggleAttr('hidden', false);
    showHintButton.element.hidden = context.hint.isEmpty;
    solutionTab.toggleAttr('hidden', context.solution.isEmpty);
    editorIsBusy = false;
  }

  @override
  String get fullDartSource => '${context.dartSource}\n${context.testMethod}\n'
      '${executionService.testResultDecoration}';

  @override
  Future<bool> handleRun() async {
    if (editorIsBusy) {
      return false;
    }

    if (context.dartSource.isEmpty) {
      unawaited(dialog.showOk(
          'No code to execute',
          'Try entering some Dart code into the "Dart" tab, then click this '
              'button again to run it.'));
      return false;
    }

    _executionButtonCount++;
    ga.sendEvent('execution', 'initiated', label: '$_executionButtonCount');

    editorIsBusy = true;
    testResultBox.hide();
    hintBox.hide();
    consoleExpandController.clear();

    var success = await super.handleRun();

    editorIsBusy = false;

    // The iframe will show Flutter output for the rest of the lifetime of the
    // app, so hide the label.
    webOutputLabel.setAttr('hidden');

    return success;
  }

  void _toggleCodeInput() {
    var editorAndConsoleContainer =
        querySelector('#editor-and-console-container')!;
    var webOutput = querySelector('#web-output')!;

    var isEditorHidden = editorAndConsoleContainer.hidden;

    if (isEditorHidden) {
      // show code input, hide UI output
      editorCodeInputTabButton!.text = 'Hide code';
      editorAndConsoleContainer.removeAttribute('hidden');
      webOutput.setAttribute('hidden', '');
      _updateShowcase(isEditorVisible: true);

      // run format to force to display the code & show caret in the editor
      _format();
    } else {
      // hide code input, show UI output
      editorCodeInputTabButton!.text = 'Show code';
      editorAndConsoleContainer.setAttribute('hidden', '');
      webOutput.removeAttribute('hidden');
      _updateShowcase();
    }
  }

  void _updateShowcase({bool isEditorVisible = false}) {
    var webOutput = querySelector('#web-output')!;
    var editorAndConsoleContainer =
        querySelector('#editor-and-console-container')!;

    splitter = flexSplit(
      <Element>[isEditorVisible ? editorAndConsoleContainer : webOutput],
      horizontal: true,
      gutterSize: 0,
      sizes: [100],
      minSize: [100],
    );
  }

  void _sendVirtualPageView(String? id) {
    var url = Uri.parse(window.location.toString());
    var newParams = Map<String, String?>.from(url.queryParameters);
    newParams['ga_id'] = id;
    var pageName = url.replace(queryParameters: newParams);
    var path = '${pageName.path}?${pageName.query}';
    ga.sendPage(pageName: path);
  }

  @override
  void displayIssues(List<AnalysisIssue> issues) {
    testResultBox.hide();
    hintBox.hide();
    analysisResultsController.display(issues);
  }

  WindowBase? get _hostWindow {
    if (window.parent != null) {
      return window.parent;
    }

    return window;
  }

  void _showInstallPage() {
    if (_modeName == 'dart' || _modeName == 'html') {
      ga.sendEvent('main', 'install-dart');
      _hostWindow!.location.href = 'https://dart.dev/get-dart';
    } else {
      ga.sendEvent('main', 'install-flutter');
      _hostWindow!.location.href = 'https://flutter.dev/get-started/install';
    }
  }

  void _format() async {
    var originalSource = userCodeEditor.document.value;
    var input = SourceRequest()..source = originalSource;

    try {
      formatButton.disabled = true;
      var result = await dartServices.format(input).timeout(serviceCallTimeout);

      busyLight.reset();
      formatButton.disabled = false;

      // Check that the user hasn't edited the source since the format request.
      if (originalSource == userCodeEditor.document.value) {
        // And, check that the format request did modify the source code.
        if (originalSource != result.newString) {
          userCodeEditor.document.updateValue(result.newString);
          unawaited(performAnalysis());
        }
      }
    } catch (e) {
      busyLight.reset();
      formatButton.disabled = false;
      print(e);
    }
  }

  void _handleAutoCompletion(KeyboardEvent e) {
    if (userCodeEditor.hasFocus && e.keyCode == KeyCode.PERIOD) {
      userCodeEditor.showCompletions(autoInvoked: true);
    }
  }

  int get initialSplitPercent {
    const defaultSplitPercentage = 70;

    var s = queryParams.initialSplit ?? defaultSplitPercentage;

    // keep the split within the range [5, 95]
    s = math.min(s, 95);
    s = math.max(s, 5);
    return s;
  }

  void _jumpTo(int line, int charStart, int charLength, {bool focus = false}) {
    var doc = userCodeEditor.document;

    doc.select(
        doc.posFromIndex(charStart), doc.posFromIndex(charStart + charLength));

    if (focus) userCodeEditor.focus();
  }

  @override
  void clearOutput() {
    consoleExpandController.clear();
  }

  @override
  bool get shouldAddFirebaseJs => hasFirebaseContent(fullDartSource);

  @override
  bool get shouldCompileDDC =>
      options.mode == EmbedMode.flutter ||
      options.mode == EmbedMode.flutter_showcase;

  @override
  void showOutput(String message, {bool error = false}) {
    consoleExpandController.showOutput(message, error: error);
  }
}

// material-components-web uses specific classes for its navigation styling,
// rather than an attribute. This class extends the tab controller code to also
// toggle that class.
class EmbedTabController extends MaterialTabController {
  final Dialog _dialog;
  bool _userHasSeenSolution = false;

  EmbedTabController(MDCTabBar tabBar, this._dialog) : super(tabBar);

  @override
  void registerTab(TabElement tab) {
    tabs.add(tab);

    try {
      tab.onClick
          .listen((_) => selectTab(tab.name, force: _userHasSeenSolution));
    } catch (e, st) {
      print('Error from registerTab: $e\n$st');
    }
  }

  /// This method will throw if the tabName is not the name of a current tab.
  @override
  Future selectTab(String? tabName, {bool force = false}) async {
    // Show a confirmation dialog if the solution tab is tapped
    if (tabName == 'solution' && !force) {
      var result = await _dialog.showYesNo(
        'Show solution?',
        'If you just want a hint, click <span style="font-weight:bold">Cancel'
            '</span> and then <span style="font-weight:bold">Hint</span>.',
        yesText: 'Show solution',
        noText: 'Cancel',
      );
      // Go back to the editor tab
      if (result == DialogResult.no) {
        tabName = 'editor';
      }
    }

    if (tabName == 'solution') {
      ga.sendEvent('view', 'solution');
      _userHasSeenSolution = true;
    }

    await super.selectTab(tabName);
  }
}

/// A container underneath the tab strip that can show or hide itself as needed.
class TabView {
  final DElement element;

  const TabView(this.element);

  void setSelected(bool selected) {
    if (selected) {
      element.clearAttr('hidden');
    } else {
      element.setAttr('hidden');
    }
  }
}

/// It's a real word, I swear.
class DisableableButton {
  DisableableButton(ButtonElement anchorElement, VoidCallback onClick) {
    _element = DElement(anchorElement);
    _element.onClick.listen((e) {
      if (!_disabled) {
        onClick();
      }
    });
  }

  static const _disabledClassName = 'disabled';

  late DElement _element;

  bool _disabled = false;

  bool get disabled => _disabled;

  set disabled(bool value) {
    _disabled = value;
    _element.toggleClass(_disabledClassName, value);
  }

  set hidden(bool value) {
    _element.toggleAttr('hidden', value);
  }
}

enum FlashBoxStyle {
  warn,
  error,
  success,
}

class FlashBox {
  /// This constructor will throw if [div] does not have a child with the
  /// flash-close class and a child with the message-container class.
  FlashBox(DivElement div) {
    _element = DElement(div);
    _messageContainer = DElement(div.querySelector('.message-container')!);

    final closeLink = DElement(div.querySelector('.close-flash-container')!);
    closeLink.onClick.listen((event) {
      hide();
    });
  }

  static const classNamesForStyles = <FlashBoxStyle, String>{
    FlashBoxStyle.warn: 'flash-warn',
    FlashBoxStyle.error: 'flash-error',
    FlashBoxStyle.success: 'flash-success',
  };

  late DElement _element;

  late DElement _messageContainer;

  void showStrings(List<String> messages, [FlashBoxStyle? style]) {
    showElements(messages.map((m) => DivElement()..text = m).toList(), style);
  }

  void showElements(List<Element> elements, [FlashBoxStyle? style]) {
    _element.clearAttr('hidden');
    _element.element.classes
        .removeWhere((s) => classNamesForStyles.values.contains(s));

    if (style != null) {
      _element.toggleClass(classNamesForStyles[style], true);
    }

    _messageContainer.clearChildren();

    for (final element in elements) {
      _messageContainer.add(element);
    }
  }

  void hide() {
    _element.setAttr('hidden');
  }

  void show() {
    _element.clearAttr('hidden');
  }
}

class ConsoleExpandController extends Console {
  final DElement expandButton;
  final DElement footer;
  final DElement expandIcon;
  final Counter? unreadCounter;
  final Function? onSizeChanged;
  final EditorUi? editorUi;
  late Splitter _splitter;
  bool _expanded;

  ConsoleExpandController({
    required Element expandButton,
    required Element footer,
    required Element expandIcon,
    required Element consoleElement,
    this.unreadCounter,
    this.onSizeChanged,
    this.editorUi,
  })  : expandButton = DElement(expandButton),
        footer = DElement(footer),
        expandIcon = DElement(expandIcon),
        _expanded = false,
        super(DElement(consoleElement),
            errorClass: 'text-red', filter: filterCloudUrls) {
    super.element.setAttr('hidden');
    footer.removeAttribute('hidden');
    expandButton.onClick.listen((_) => _toggleExpanded());
  }

  @override
  void showOutput(String message, {bool error = false}) {
    super.showOutput(message, error: error);
    if (!_expanded) {
      unreadCounter!.increment();
    }
  }

  @override
  void clear() {
    super.clear();
    unreadCounter!.clear();
  }

  void open() {
    if (!_expanded) {
      _toggleExpanded();
    }
  }

  void close() {
    if (_expanded) {
      _toggleExpanded();
    }
  }

  void _toggleExpanded() {
    _expanded = !_expanded;
    if (_expanded) {
      _initSplitter();
      _splitter.setSizes([60, 40]);
      element.toggleAttr('hidden', false);
      expandIcon.element.innerText = 'expand_more';
      footer.toggleClass('footer-top-border', false);
      unreadCounter!.clear();
    } else {
      _splitter.setSizes([100, 0]);
      element.toggleAttr('hidden', true);
      expandIcon.element.innerText = 'expand_less';
      footer.toggleClass('footer-top-border', true);
      try {
        _splitter.destroy();
      } on NoSuchMethodError {
        // dart2js throws NoSuchMethodError (dartdevc is ok)
        // TODO(ryjohn): why does this happen?
      }
    }
    onSizeChanged!();
  }

  void _initSplitter() {
    var splitterElements = [
      querySelector('#editor-container')!,
      querySelector('#console-output-footer')!,
    ];
    _splitter = flexSplit(
      splitterElements,
      horizontal: false,
      gutterSize: defaultSplitterWidth,
      sizes: [60, 40],
      minSize: [32, 32],
    );
    editorUi!.listenForResize(splitterElements[0]);
  }
}

class EmbedContext implements ContextBase {
  final Editor userCodeEditor;
  final Editor? htmlEditor;
  final Editor? cssEditor;
  final Editor testEditor;
  final Editor solutionEditor;

  Document? _dartDoc;
  Document? _htmlDoc;
  Document? _cssDoc;

  String hint = '';

  String _solution = '';

  String get testMethod => testEditor.document.value;

  set testMethod(String value) {
    testEditor.document.value = value;
  }

  String get solution => _solution;

  set solution(String value) {
    _solution = value;
    solutionEditor.document.value = value;
  }

  final _dartDirtyController = StreamController.broadcast();

  final _dartReconcileController = StreamController.broadcast();

  EmbedContext(this.userCodeEditor, this.testEditor, this.solutionEditor,
      this.htmlEditor, this.cssEditor) {
    _dartDoc = userCodeEditor.document;
    _htmlDoc = htmlEditor?.document;
    _cssDoc = cssEditor?.document;
    _dartDoc!.onChange.listen((_) => _dartDirtyController.add(null));
    _createReconciler(_dartDoc!, _dartReconcileController, 1250);
  }

  Document? get dartDocument => _dartDoc;

  @override
  String get dartSource => _dartDoc!.value;

  @override
  String get htmlSource => _htmlDoc?.value ?? '';

  @override
  String get cssSource => _cssDoc?.value ?? '';

  set dartSource(String value) {
    userCodeEditor.document.value = value;
  }

  set htmlSource(String value) {
    htmlEditor?.document.value = value;
  }

  set cssSource(String value) {
    cssEditor?.document.value = value;
  }

  String get activeMode => userCodeEditor.mode;

  Stream get onDartDirty => _dartDirtyController.stream;

  Stream get onDartReconcile => _dartReconcileController.stream;

  void markDartClean() => _dartDoc!.markClean();

  /// Restore the focus to the last focused editor.
  void focus() => userCodeEditor.focus();

  void _createReconciler(Document doc, StreamController controller, int delay) {
    Timer? timer;
    doc.onChange.listen((_) {
      if (timer != null) timer!.cancel();
      timer = Timer(Duration(milliseconds: delay), () {
        controller.add(null);
      });
    });
  }

  /// Return true if the current cursor position is in a whitespace char.
  bool cursorPositionIsWhitespace() {
    // TODO(DomesticMouse): implement with CodeMirror integration
    return false;
  }

  @override
  bool get isFocused => userCodeEditor.hasFocus;
}

final RegExp _flutterUrlExp =
    RegExp(r'(https:[a-zA-Z0-9_=%&\/\-\?\.]+flutter_web\.js)(:\d+:\d+)');
final RegExp _dartUrlExp =
    RegExp(r'(https:[a-zA-Z0-9_=%&\/\-\?\.]+dart_sdk\.js)(:\d+:\d+)');

String filterCloudUrls(String trace) {
  return trace
      .replaceAllMapped(
          _flutterUrlExp, (m) => '[Flutter SDK Source]${m.group(2)}')
      .replaceAllMapped(_dartUrlExp, (m) => '[Dart SDK Source]${m.group(2)}');
}
