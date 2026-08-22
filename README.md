# 📚 Living Books

> A readable-book framework for **Project Zomboid**.

**Living Books** is a framework that adds fully readable books to Project Zomboid. It provides the systems required to load, display, search and manage long-form written content inside the game.

The project is designed to make creating custom books as simple as possible while keeping the runtime system lightweight and efficient.

---

## 🧩 Project Components

This repository contains the tools and resources required to work with Living Books.

### 📖 Living Books

The main Project Zomboid framework.

It handles:

* Book loading
* Chapter and page generation
* Page navigation
* Text searching
* Reading progress
* Book data management
* In-game book presentation

### 🛠️ LivingBooksTool

**LivingBooksTool** is the companion utility used to create books compatible with Living Books.

Instead of manually creating and formatting all the required files, the tool handles the conversion and generation process for you.

The latest version can be found in:

**[Releases](../../releases)**

If you're interested in creating your own books, **LivingBooksTool is the recommended way to generate them.**

---

## 🚀 Getting Started

### For Players

If you're looking for the actual Project Zomboid mod, visit the Steam Workshop page:

**[Living Books — Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3549484875)**

### For Creators

If you want to create your own books:

1. Download the latest **LivingBooksTool** from [Releases](../../releases).
2. Prepare the content of your book.
3. Use LivingBooksTool to generate the required Living Books files.
4. Add the generated files to your Project Zomboid mod.
5. Launch the game and test your book.

A more detailed creation guide can be found in the repository.

---

## 📦 Releases

Compiled versions of **LivingBooksTool** and other downloadable project components are available under:

**[GitHub Releases](../../releases)**

Each release should contain the appropriate files and version information required to use that version of the tool.

---

## 🗂️ Repository Structure

```text
Living-Books/
│
├── LivingBooks/
│   └── Project Zomboid mod files
│
├── LivingBooksTool/
│   └── Book creation tool
│
├── Documentation/
│   └── Guides and documentation
│
└── README.md
```

> The repository structure may change as the project develops.

---

## 🔧 Development

Living Books is split between the in-game framework and the external tooling used to create book content.

Changes to either component may affect compatibility, so please check the relevant documentation before modifying the project.

When contributing, keep changes focused and document any changes that affect the book format or tool output.

---

## 📚 Book Format

Living Books uses a structured format to represent book content, allowing large books to be divided into chapters and pages while keeping the resulting data relatively small.

The format is designed around three goals:

* **Simple** — easy to generate and understand.
* **Efficient** — minimal overhead for large books.
* **Extensible** — capable of supporting additional functionality in the future.

Documentation for the book format will be maintained in the repository.

---

## 🐛 Issues & Bug Reports

Found a bug?

Before opening an issue:

1. Check the existing issues.
2. Make sure you're using the latest release.
3. Confirm whether the issue occurs with a clean installation.
4. Include your Project Zomboid version and Living Books version.
5. Provide reproduction steps and relevant logs whenever possible.

**[Open an Issue](../../issues)**

---

## 💡 Feature Requests

Have an idea for Living Books or LivingBooksTool?

Suggestions are welcome. When proposing a feature, explain:

* What problem it solves.
* How you expect it to work.
* Why it would be useful.
* Whether it affects the existing book format or compatibility.

**[Open a Feature Request](../../issues/new)**

---

## 🤝 Contributing

Contributions are welcome.

If you want to contribute:

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
cd YOUR_REPOSITORY
```

Create a branch for your changes, make your modifications, test them, and submit a pull request.

Please keep pull requests focused on a single feature, fix, or improvement whenever possible.

---

## 📄 License

See the [LICENSE](LICENSE) file for information about the terms under which this project can be used, modified, and distributed.

---

## 🔗 Links

* 📦 **[Releases](../../releases)**
* 🐛 **[Issues](../../issues)**
* 🔀 **[Pull Requests](../../pulls)**
* 🎮 **[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3549484875)**

---

<p align="center">
  <b>Living Books</b><br>
  Bringing readable stories to Project Zomboid.
</p>
