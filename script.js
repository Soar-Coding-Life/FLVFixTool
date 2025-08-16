
document.addEventListener('DOMContentLoaded', () => {
    const languageToggleBtn = document.getElementById('language-toggle');
    const themeToggleBtn = document.getElementById('theme-toggle');
    const translatableElements = document.querySelectorAll('[data-key]');

    const translations = {
        "heroTitle": "终极FLV修复与编辑工具",
        "heroSubtitle": "轻松检查、修复损坏的时间戳并编辑您的闪存视频（FLV）文件的元数据。一款为速度和简洁性而生的原生macOS应用程序。",
        "downloadButton": "下载macOS版",
        "downloadNote": "仅支持MacOS 14.0 或更高版本。",
        "featuresTitle": "主要功能",
        "feature1Title": "检查与分析",
        "feature1Desc": "深入了解您FLV文件的结构。在清晰、有组织的表格中查看头部信息、元数据和单个标签。",
        "feature2Title": "修复损坏的文件",
        "feature2Desc": "自动修复常见的FLV问题，如错误的持续时间和损坏的时间戳，使您的文件可以再次播放。",
        "feature3Title": "编辑元数据",
        "feature3Desc": "轻松修改`onMetaData`脚本标签。更改尺寸、帧率和其他关键属性，然后将您的更改保存到新文件中。",
        "footerText": "© 2025 FLVFixTool. 版权所有。"
    };

    let currentLanguage = 'en';
    let currentTheme = 'dark';

    // --- Language Switching ---
    const setLanguage = (language) => {
        currentLanguage = language;
        translatableElements.forEach(el => {
            const key = el.dataset.key;
            if (language === 'zh') {
                if (!el.dataset.langEn) {
                    el.dataset.langEn = el.innerText;
                }
                el.innerText = translations[key];
                languageToggleBtn.innerText = "🇨🇳";
            } else {
                if (el.dataset.langEn) {
                    el.innerText = el.dataset.langEn;
                }
                languageToggleBtn.innerText = "🇺🇸";
            }
        });
        localStorage.setItem('language', language);
    };

    languageToggleBtn.addEventListener('click', () => {
        setLanguage(currentLanguage === 'en' ? 'zh' : 'en');
    });

    // --- Theme Switching ---
    const setTheme = (theme) => {
        currentTheme = theme;
        if (theme === 'light') {
            document.body.classList.add('light-mode');
            themeToggleBtn.innerText = '☀️';
        } else {
            document.body.classList.remove('light-mode');
            themeToggleBtn.innerText = '🌙';
        }
        localStorage.setItem('theme', theme);
    };

    themeToggleBtn.addEventListener('click', () => {
        setTheme(currentTheme === 'dark' ? 'light' : 'dark');
    });

    // --- Initialization ---
    const savedTheme = localStorage.getItem('theme') || 'dark';
    const savedLanguage = localStorage.getItem('language') || 'en';

    setTheme(savedTheme);
    setLanguage(savedLanguage);
});
