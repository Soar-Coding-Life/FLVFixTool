window.addEventListener('load', () => {
    const carousels = document.querySelectorAll("[aria-roledescription='carousel']");
    carousels.forEach(initCarousel);
});

function initCarousel(carousel) {
    const slidesContainer = carousel.querySelector(".slides");
    const slides = Array.from(carousel.querySelectorAll(".slide"));
    const nextBtn = carousel.querySelector(".next");
    const prevBtn = carousel.querySelector(".prev");
    const dotsContainer = carousel.querySelector(".carousel-dots");
    const numSlides = slides.length;

    if (numSlides < 2) {
        if (nextBtn) nextBtn.style.display = 'none';
        if (prevBtn) prevBtn.style.display = 'none';
        return;
    }

    let currentIndex = 0;

    const getSlideWidth = () => slides[0].offsetWidth;

    const updateCarousel = () => {
        const slideWidth = getSlideWidth();
        slidesContainer.style.transform = `translateX(-${currentIndex * slideWidth}px)`;

        // Update button states
        prevBtn.disabled = currentIndex === 0;
        nextBtn.disabled = currentIndex === numSlides - 1;

        updateDots();
    };

    const moveTo = (index) => {
        if (index < 0 || index >= numSlides) return;
        currentIndex = index;
        updateCarousel();
    };

    const moveToNext = () => {
        if (currentIndex < numSlides - 1) {
            moveTo(currentIndex + 1);
        }
    };

    const moveToPrev = () => {
        if (currentIndex > 0) {
            moveTo(currentIndex - 1);
        }
    };

    const updateDots = () => {
        if (!dotsContainer) return;
        dotsContainer.innerHTML = "";
        for (let i = 0; i < numSlides; i++) {
            const button = document.createElement("button");
            button.setAttribute('aria-label', `Go to slide ${i + 1}`);
            if (i === currentIndex) {
                button.classList.add("active");
            }
            button.addEventListener("click", () => moveTo(i));
            dotsContainer.appendChild(button);
        }
    };

    // --- Event Listeners ---
    if (nextBtn) {
        nextBtn.addEventListener("click", moveToNext);
    }

    if (prevBtn) {
        prevBtn.addEventListener("click", moveToPrev);
    }

    // --- Initialization & Resize Handling ---
    const observer = new ResizeObserver(() => {
        updateCarousel();
    });
    observer.observe(carousel);

    updateCarousel(); // Initial setup
}