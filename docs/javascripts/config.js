window.MathJax = {
  tex: {
    inlineMath: [["\\(", "\\)"]],
    displayMath: [["\\[", "\\]"]],
    processEscapes: true,
    processEnvironments: true
  },
  options: {
    ignoreHtmlClass: ".*|",
    processHtmlClass: "arithmatex"
  },
  startup: {
    pageReady() {
      return MathJax.startup.defaultPageReady().then(() => {
        // Subscribe only after MathJax has loaded and typeset the first page.
        let initial = true;
        document$.subscribe(() => {
          if (initial) {
            initial = false;
            return;
          }
          MathJax.typesetClear();
          MathJax.texReset();
          MathJax.typesetPromise().catch(error => {
            console.error("MathJax rendering failed", error);
          });
        });
      });
    }
  }
};
