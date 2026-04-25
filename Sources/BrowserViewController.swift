import UIKit
import WebKit
import Combine

// MARK: - BrowserViewController

class BrowserViewController: UIViewController {

    // MARK: Properties

    private let sessions: [TabSession]
    private var activeIndex: Int = 0
    private var isEditingURL: Bool = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: UI Parts

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let urlField = UITextField()
    private let reloadButton = UIButton(type: .system)
    private let trashButton = UIButton(type: .system)

    private let footerView = UIView()
    private var tabButtons: [UIButton] = []
    private let memoButton = UIButton(type: .system)

    private var webViewContainer = UIView()

    private var memoView: UITextView?
    private var showMemo: Bool = false

    // MARK: Init

    init(sessions: [TabSession]) {
        self.sessions = sessions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebViewContainer()
        setupHeader()
        setupFooter()
        setupConstraints()
        switchTab(to: 0)
        observeURL()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    // MARK: Setup

    private func setupWebViewContainer() {
        webViewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webViewContainer)

        for session in sessions {
            let wv = session.webView
            wv.translatesAutoresizingMaskIntoConstraints = false
            wv.alpha = 0
            webViewContainer.addSubview(wv)
            NSLayoutConstraint.activate([
                wv.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
                wv.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor),
                wv.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
            ])
        }
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .systemBackground
        view.addSubview(headerView)

        // 戻る
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)

        // 進む
        forwardButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        forwardButton.addTarget(self, action: #selector(goForward), for: .touchUpInside)

        // URLフィールド
        urlField.borderStyle = .roundedRect
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.returnKeyType = .go
        urlField.delegate = self

        // リロード
        reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        reloadButton.addTarget(self, action: #selector(reload), for: .touchUpInside)

        // ゴミ箱
        trashButton.setImage(UIImage(systemName: "trash"), for: .normal)
        trashButton.tintColor = .systemRed
        trashButton.addTarget(self, action: #selector(clearCookies), for: .touchUpInside)

        for v in [backButton, forwardButton, urlField, reloadButton, trashButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 36),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            forwardButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 36),

            urlField.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 4),
            urlField.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            urlField.heightAnchor.constraint(equalToConstant: 36),

            reloadButton.leadingAnchor.constraint(equalTo: urlField.trailingAnchor, constant: 4),
            reloadButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 36),

            trashButton.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 4),
            trashButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            trashButton.widthAnchor.constraint(equalToConstant: 36),
            trashButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
        ])
    }

    private func setupFooter() {
        footerView.translatesAutoresizingMaskIntoConstraints = false
        footerView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)

        // すりガラス
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(blur)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: footerView.topAnchor),
            blur.bottomAnchor.constraint(equalTo: footerView.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
        ])

        view.addSubview(footerView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(stack)

        for i in 0..<5 {
            let btn = UIButton(type: .system)
            btn.setTitle("\(i + 1)", for: .normal)
            btn.titleLabel?.font = .boldSystemFont(ofSize: 17)
            btn.tag = i
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(btn)
            tabButtons.append(btn)
            btn.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 1.0/6.0).isActive = true
        }

        memoButton.setImage(UIImage(systemName: "note.text"), for: .normal)
        memoButton.addTarget(self, action: #selector(toggleMemo), for: .touchUpInside)
        stack.addArrangedSubview(memoButton)
        memoButton.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 1.0/6.0).isActive = true

        // stackはfooterViewの上部52ptだけ（ホームインジケーターより上）
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: footerView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            stack.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func setupConstraints() {
        let safeArea = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            // ヘッダー：safeAreaの上端 〜 固定高さ52
            headerView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 52),

            // WebView：ヘッダー下 〜 フッター上
            webViewContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            webViewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webViewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webViewContainer.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            // フッター：safeAreaの下端まで（ホームインジケーター含む）
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor), // ← safeAreaではなくview
            footerView.topAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -52),
        ])
    }

    // MARK: Tab

    private func switchTab(to index: Int) {
        sessions[activeIndex].saveCookies()
        sessions[activeIndex].webView.alpha = 0
        activeIndex = index
        sessions[activeIndex].webView.alpha = 1
        urlField.text = sessions[activeIndex].currentURL
        if sessions[activeIndex].webView.url == nil {
            sessions[activeIndex].loadInitialURL()
        }
        updateTabHighlight()
        observeURL()
    }

    private func updateTabHighlight() {
        for (i, btn) in tabButtons.enumerated() {
            btn.backgroundColor = i == activeIndex
                ? UIColor.systemBlue.withAlphaComponent(0.2)
                : .clear
        }
    }

    private func observeURL() {
        cancellables.removeAll()
        sessions[activeIndex].$currentURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                guard let self, !self.isEditingURL else { return }
                self.urlField.text = url
            }
            .store(in: &cancellables)
    }

    // MARK: Actions

    @objc private func goBack() { sessions[activeIndex].webView.goBack() }
    @objc private func goForward() { sessions[activeIndex].webView.goForward() }
    @objc private func reload() { sessions[activeIndex].webView.reload() }

    @objc private func tabTapped(_ sender: UIButton) {
        switchTab(to: sender.tag)
    }

    @objc private func clearCookies() {
        let alert = UIAlertController(
            title: "クッキーを削除",
            message: "タブ\(activeIndex + 1)のクッキーと履歴を削除します",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "削除", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.sessions[self.activeIndex].clearCookies {
                DispatchQueue.main.async {
                    self.sessions[self.activeIndex].loadInitialURL()
                    self.urlField.text = "https://duckduckgo.com"
                }
            }
        })
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func toggleMemo() {
        showMemo.toggle()
        if showMemo {
            let tv = UITextView(frame: CGRect(x: 0, y: 0, width: 250, height: 200))
            tv.text = sessions[activeIndex].memo
            tv.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.9)
            tv.layer.cornerRadius = 10
            tv.translatesAutoresizingMaskIntoConstraints = false
            webViewContainer.addSubview(tv)
            NSLayoutConstraint.activate([
                tv.widthAnchor.constraint(equalToConstant: 250),
                tv.heightAnchor.constraint(equalToConstant: 200),
                tv.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor, constant: -16),
                tv.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor, constant: -16),
            ])
            memoView = tv
            memoButton.tintColor = .systemOrange
        } else {
            memoView?.removeFromSuperview()
            memoView = nil
            memoButton.tintColor = .label
        }
    }

    @objc private func appDidEnterBackground() {
        for session in sessions { session.saveCookies() }
    }

    private func loadURL(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if trimmed.contains(".") && !trimmed.contains(" ") {
            path = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            path = "https://duckduckgo.com/?q=\(query)"
        }
        if let url = URL(string: path) {
            sessions[activeIndex].webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - UITextFieldDelegate

extension BrowserViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        isEditingURL = true
    }
    func textFieldDidEndEditing(_ textField: UITextField) {
        isEditingURL = false
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        isEditingURL = false
        loadURL(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }
}
