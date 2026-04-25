import UIKit
import WebKit
import Combine

class BrowserViewController: UIViewController {

    private let sessions: [TabSession]
    private var activeIndex: Int = 0
    private var isEditingURL: Bool = false
    private var cancellables = Set<AnyCancellable>()

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let urlField = UITextField()
    private let reloadButton = UIButton(type: .system)
    private let trashButton = UIButton(type: .system)

    private let footerView = UIView()
    private var tabButtons: [UIButton] = []
    private let memoButton = UIButton(type: .system)
    private let tabStack = UIStackView()

    private let webViewContainer = UIView()
    private var memoView: UITextView?
    private var showMemo = false

    init(sessions: [TabSession]) {
        self.sessions = sessions
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebViewContainer()
        setupHeader()
        setupFooter()
        setupConstraints()
        switchTab(to: 0)

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    // MARK: - Setup

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

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)

        forwardButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        forwardButton.addTarget(self, action: #selector(goForward), for: .touchUpInside)

        urlField.borderStyle = .roundedRect
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.returnKeyType = .go
        urlField.delegate = self

        reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        reloadButton.addTarget(self, action: #selector(reload), for: .touchUpInside)

        trashButton.setImage(UIImage(systemName: "trash"), for: .normal)
        trashButton.tintColor = .systemRed
        trashButton.addTarget(self, action: #selector(clearCookies), for: .touchUpInside)

        let controlStack = UIStackView(arrangedSubviews: [backButton, forwardButton, urlField, reloadButton, trashButton])
        controlStack.axis = .horizontal
        controlStack.spacing = 4
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(controlStack)

        for btn in [backButton, forwardButton, reloadButton, trashButton] {
            btn.widthAnchor.constraint(equalToConstant: 36).isActive = true
        }

        // コンテンツはsafeAreaの下から52pt分
        NSLayoutConstraint.activate([
            controlStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            controlStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            controlStack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8),
            controlStack.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func setupFooter() {
        footerView.translatesAutoresizingMaskIntoConstraints = false
        footerView.backgroundColor = .systemBackground

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

        tabStack.axis = .horizontal
        tabStack.distribution = .fillEqually
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(tabStack)

        for i in 0..<5 {
            let btn = UIButton(type: .system)
            btn.setTitle("\(i + 1)", for: .normal)
            btn.titleLabel?.font = .boldSystemFont(ofSize: 17)
            btn.tag = i
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabStack.addArrangedSubview(btn)
            tabButtons.append(btn)
        }

        memoButton.setImage(UIImage(systemName: "note.text"), for: .normal)
        memoButton.addTarget(self, action: #selector(toggleMemo), for: .touchUpInside)
        tabStack.addArrangedSubview(memoButton)

        // tabStackはsafeAreaの上端から52ptだけ（ホームインジケーターより上）
        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: footerView.topAnchor),
            tabStack.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            tabStack.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func setupConstraints() {
        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            // ヘッダー：画面の一番上(view.top)から始めて、safeArea.topの下52ptまで
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: safe.topAnchor, constant: 52),

            // WebView：ヘッダー下からフッター上まで
            webViewContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            webViewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webViewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webViewContainer.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            // フッター：画面の一番下(view.bottom)まで、safeArea.bottomの上52ptから始まる
            footerView.topAnchor.constraint(equalTo: safe.bottomAnchor, constant: -52),
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Tab

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
                ? UIColor.systemBlue.withAlphaComponent(0.2) : .clear
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

    // MARK: - Actions

    @objc private func goBack() { sessions[activeIndex].webView.goBack() }
    @objc private func goForward() { sessions[activeIndex].webView.goForward() }
    @objc private func reload() { sessions[activeIndex].webView.reload() }
    @objc private func tabTapped(_ sender: UIButton) { switchTab(to: sender.tag) }

    @objc private func clearCookies() {
        let alert = UIAlertController(
            title: "クッキーを削除",
            message: "タブ\(activeIndex + 1)のクッキーと履歴を削除します",
            preferredStyle: .alert)
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
            let tv = UITextView()
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
    func textFieldDidBeginEditing(_ textField: UITextField) { isEditingURL = true }
    func textFieldDidEndEditing(_ textField: UITextField) { isEditingURL = false }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        isEditingURL = false
        loadURL(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }
}
