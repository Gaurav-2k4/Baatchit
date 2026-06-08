import 'package:flutter/material.dart';
import 'signup.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {

  final loginController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;

  Future<void> handleLogin() async {
    String input = loginController.text.trim();
    String password = passwordController.text;

    if (input.isEmpty || password.isEmpty) {
      showMessage("Please fill all fields");
      return;
    }

    setState(() => isLoading = true);

    try {
      String email = input;

      // 🔥 Username login support
      if (!input.contains("@")) {
        QuerySnapshot snapshot = await FirebaseFirestore.instance
            .collection("users")
            .where("username", isEqualTo: input)
            .limit(1)
            .get();

        if (snapshot.docs.isEmpty) {
          showMessage("Username not found");
          setState(() => isLoading = false);
          return;
        }

        email = snapshot.docs.first["email"];
      }

      // 🔥 Firebase login
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      showMessage("Login Successful");

      // ✅ NO navigation here
      // AuthCheck will automatically redirect to HomeScreen

    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        showMessage("User not found");
      } else if (e.code == 'wrong-password') {
        showMessage("Incorrect password");
      } else {
        showMessage(e.message ?? "Login failed");
      }
    } catch (e) {
      showMessage("Something went wrong");
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  void showMessage(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    loginController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              const Icon(Icons.chat, size: 70, color: Colors.green),

              const SizedBox(height: 10),

              const Text(
                "Baatchit",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 30),

              TextField(
                controller: loginController,
                decoration: InputDecoration(
                  labelText: "Email or Username",
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: "Password",
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : handleLogin,
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("Login"),
                ),
              ),

              const SizedBox(height: 15),

              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SignupScreen()),
                  );
                },
                child: const Text(
                  "Don't have an account? Sign Up",
                  style: TextStyle(color: Colors.green),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
