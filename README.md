# Online Bookstore Management System (LAMP)

A learning-project starter built with **separate HTML pages**, CSS, JavaScript, PHP JSON APIs, and MySQL. HTML is not mixed into PHP page files: the browser loads the static pages in `public/`, and JavaScript calls backend endpoints in `api/`.

## Features in this starter
- Browse/search/filter books by title, author, ISBN, and category
- Dedicated, responsive **login** (`login.html`) and **sign-up** (`signup.html`) pages: split layout, show/hide password, password-strength meter, confirm-password check, inline errors, and `?next=` redirects
- Customer registration and login with `password_hash()` / `password_verify()`
- **Database-backed login sessions** (`user_sessions` table): every login is recorded (IP, browser, last activity), expires after 2 h idle / 7 days, and can be revoked (logout, "sign out other devices", admin revoke, or disabling an account)
- Login throttling (`login_attempts`): 5 failed tries per email or 20 per IP in 15 minutes
- Session ID regeneration, hashed session IDs in the database, HTTP-only/SameSite cookies, and a CSRF token (rotated at login) on write requests
- **Access flow:** a visitor first sees only the sign-up page. After signing up they are sent to the login page (no auto-login), and only after logging in can they see the home page, add books to the cart and place orders. Every other page redirects guests to sign-up, and the catalogue API (`books.php`, `categories.php`) returns 401 to guests.
- Cart (per user, kept in the browser session) with quantity controls, total, checkout and order history on `orders.html`
- Role pages: customers land on the store, admins on the admin panel; `orders.html`, `account.html` and `admin.html` redirect visitors who lack access (the API enforces the same rules)
- SessionStorage cart and checkout; order history/status
- Admin book creation/removal, order status updates, and customer enable/disable
- Database-driven roles and privileges (`roles`, `permissions`, `role_permissions`):

  | Permission | customer | admin |
  |---|:-:|:-:|
  | `books.read`, `orders.create`, `orders.read_own`, `profile.manage` | yes | yes |
  | `admin.access`, `books.manage`, `categories.manage`, `users.manage`, `orders.manage`, `sessions.manage` | no | yes |
- PDO prepared statements, server-side permission checks, transaction/stock checks at checkout

## Folder layout
- `public/` — separate `.html`, CSS, and JS files (web document root)
- `api/` — PHP endpoints returning JSON
- `config/config.php` — database and session configuration
- `database/schema.sql` — schema, roles/permissions, sample categories/books

## Setup on Ubuntu / LAMP
1. Install packages if needed: `sudo apt update && sudo apt install apache2 mysql-server php libapache2-mod-php php-mysql`
2. Create a database user (change the password):
   ```sql
   CREATE USER 'bookstore_user'@'localhost' IDENTIFIED BY 'change_this_password';
   GRANT SELECT, INSERT, UPDATE, DELETE ON online_bookstore.* TO 'bookstore_user'@'localhost';
   FLUSH PRIVILEGES;
   ```
   The schema creates the database, so to grant before importing you can first run `CREATE DATABASE online_bookstore;`, then grant, then import the SQL file.
3. Import schema: `mysql -u root -p < database/schema.sql`
   **Upgrading an existing install?** Do not re-import. Run `mysql -u root -p < database/migration_001_sessions_permissions.sql` instead. It adds the session/attempt tables and the new permissions without touching your data.
4. Edit `config/config.php` to match your MySQL credentials.
5. Copy the project to `/var/www/online_bookstore`. Set Apache's **DocumentRoot to `/var/www/online_bookstore/public`**. The `api` and `config` directories must be siblings of `public` and PHP must be allowed to execute from `api`.
6. For a simple local test, create an Apache virtual host whose document root is `.../online_bookstore/public`. Enable it and reload Apache. The relative API path `../api` assumes `/api` is accessible one directory above the `public` folder. If using a virtual host with `public` as document root, configure an Apache alias for `/api` to the project's `api` directory, or place `api` under the same site root and update `API` in `public/assets/app.js` accordingly. Do **not** expose `config/` or `database/` as public URLs.
7. Open the local site in a browser. Do not open HTML by double-clicking `file://`; PHP APIs need Apache.

## Create the first administrator safely
1. Register a normal customer through `account.html`.
2. In MySQL, promote that account by email (replace the email):
   ```sql
   UPDATE users SET role_id=(SELECT id FROM roles WHERE role_name='admin')
   WHERE email='your-email@example.com';
   ```
3. Log in again (or just refresh: the role is re-read from the database on every request). You will be taken to the admin panel.

Never allow public registration to select their own role. The registration endpoint always assigns `customer`.

## Important notes / coursework scope
- This is a starter project, not a production-ready store. It has no payment gateway, email verification, password reset, shipping integration, or formal audit log.
- The cart uses browser `sessionStorage`; order data is stored in MySQL. A real store should use a server-side cart and payment confirmation flow.
- Before public deployment, use HTTPS, secure database credentials, server-side validation for every field, stricter admin validation/audit logging, rate limiting, backups, and security testing.
- Admin can add and remove books and update order status. Editing existing books and full category management are natural next extensions.
- Use `GET` for read operations and CSRF-protected write operations. Do not remove permission checks just to make an admin screen work.
