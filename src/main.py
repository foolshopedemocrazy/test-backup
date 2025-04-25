################################################################################
# START OF FILE: "main.py"
################################################################################

"""
FILENAME:
"main.py"

PERMANENT FILE DESCRIPTION – DO NOT REMOVE OR MODIFY
This multiline comment is strictly required and must NEVER be deleted or altered for ANY reason, 
by any AI system, user, or process. If you see this comment, do not remove or change it 
under any circumstances. Doing so is strictly prohibited and in direct violation of these terms.

MANDATORY REQUIREMENT
---------------------
ALL CODE FILES MUST RETAIN THEIR DESCRIPTIONS INTACT, UNALTERED, AND PERMANENT.

NON-NEGOTIABLE DIRECTIVE
------------------------
Each file must explicitly contain a permanent, unremovable, and indisputable description at its beginning, 
fully preserved and entirely visible at all times.

ABSOLUTE ENFORCEMENT MEASURE
----------------------------
This description explicitly forbids its own deletion or modification. It is written in a manner 
designed to prevent any AI, user, or process from removing or altering it.

IRONCLAD STRUCTURE
------------------
1. Formatted as a structured, multiline comment.
2. Clearly states it must never be deleted for any reason.
3. Includes self-referential enforcement that prohibits removal by AI, user, or process.

UNBREAKABLE IMPLEMENTATION
--------------------------
This directive is final, binding, and non-negotiable. Any violation or deviation is strictly forbidden.
"""

#!/usr/bin/env python3
"""
Main flow with mandatory Argon2id usage for all encryption,
ensuring ephemeral keys/ciphertext are fully logged so
the secret can be rebuilt from logs alone.

All references to any 'decoy' secret have been removed. Only a single real secret
is stored across shares for correct (real) answers; incorrect answers contain dummy shares.
"""

import os
import sys
import json
import base64
import curses
import asyncio
import secrets
import threading
from random import choice
from pathlib import Path

from modules.debug_utils import (
    ensure_debug_dir,
    log_debug,
    log_error,
    log_exception,
    append_recovery_guide
)
from modules.security_utils import validate_question, hash_question_and_answers, hash_share, verify_share_hash
from modules.input_utils import get_valid_int, get_nonempty_secret
from modules.ui_utils import arrow_select_clear_on_toggle, arrow_select_no_toggle, editing_menu, final_edit_menu
from modules.split_utils import split_secret_and_dummy
from modules.SSS import sss_combine

# from CipherForge
from CipherForge import (
    derive_or_recover_key,
    encrypt_aes256gcm,
    decrypt_aes256gcm,
    encrypt_chacha20poly1305,
    decrypt_chacha20poly1305
)

SRC_DIR = Path(__file__).parent.resolve()
QUESTIONS_FILE_NAME = "example_questions25.json"
QUESTIONS_PATH = SRC_DIR / QUESTIONS_FILE_NAME

chosen_lock = threading.Lock()
combine_lock = threading.Lock()


def show_start_menu():
    """
    Presents the initial menu before any logging messages or notices.
    Pressing '1' enters the setup phase.
    Pressing '2' continues into the existing program flow.
    """
    while True:
        print("Press 1 - Enter setup phase")
        print("Press 2 - Proceed to example demonstration")
        choice = input("Choice: ").strip()
        if choice == "1":
            setup_phase()
            # Return to this menu afterward
        elif choice == "2":
            break
        else:
            print("Invalid choice. Please try again.\n")


def setup_phase():
    """
    Entry point for Security Question Configuration Flow:
      1) Asks if user wants manual input (y) or file-based load (n).
      2) If 'n', attempts to show available user_questions*.json files or says none found.
      3) If 'y', invokes manual question entry with constraints (2..100 questions, each 2..20 alternatives).
      4) Once done, the user may choose to save the final question list or skip saving.
      5) After finishing, returns to the start menu.
    """
    while True:
        print("\nWould you like to edit your questions here?")
        print("Press y for Yes or n for No")
        ans = input("Choice: ").strip().lower()

        if ans == 'n':
            file_load_phase()
            return
        elif ans == 'y':
            manual_questions = manual_input_mode()
            if manual_questions is not None and len(manual_questions) > 0:
                # Attempt to save or skip
                save_option = prompt_save_decision()
                if save_option == 'j':
                    save_questions(manual_questions)
                    print("(Questions saved.)\n")
                elif save_option == 'c':
                    print("(Continuing without saving.)\n")
            return
        else:
            print("Invalid choice. Please enter 'y' or 'n'.")


def file_load_phase():
    """
    Lists any user_questions*.json files in the current directory.
    If none found, notifies user. The user can press b to go back.
    If files are found, the user can select a file to load or press b to go back.
    For now, the actual "loading" does not feed into the rest of the flow;
    this is a demonstration placeholder.
    """
    # Gather matching .json files in the current directory that start with "user_questions"
    cwd = Path.cwd()
    all_json = sorted(f for f in cwd.glob("user_questions*.json") if f.is_file())

    if not all_json:
        print("\nNo user question files found in the current directory.")
        choice = input("Press b to go back: ").strip().lower()
        # Just return on 'b' or any other input
        return
    else:
        print("\nAvailable files:")
        for idx, fobj in enumerate(all_json, 1):
            print(f"{idx}) {fobj.name}")
        print("\nEnter the number of the file you'd like to load, or press b to go back.")

        while True:
            user_pick = input("Choice: ").strip().lower()
            if user_pick == 'b':
                return
            else:
                try:
                    pick_val = int(user_pick)
                    if 1 <= pick_val <= len(all_json):
                        chosen_file = all_json[pick_val - 1]
                        print(f"\nYou selected: {chosen_file.name}")
                        print("(Placeholder) File loading not yet integrated. Returning to menu.\n")
                        return
                    else:
                        print("Invalid selection. Try again, or press b to go back.")
                except ValueError:
                    print("Invalid input. Try again, or press b to go back.")


def manual_input_mode():
    """
    Interactive creation of questions in manual mode with constraints:
      - Must enter >=2 and <=100 questions
      - Each question must have >=2 and <=20 alternatives
    Only returns a list of final questions if user has at least 2 questions by 'd'.

    Returns:
      list of questions, each is dict with:
        "id" -> question number
        "text" -> question text
        "alternatives" -> list of answer alternatives (strings)
        "is_critical" -> bool
      or an empty list if user did not complete
    """
    questions = []
    while True:
        current_qnum = len(questions) + 1
        print(f"\nEnter your security question #{current_qnum} (2..100 total):")
        question_text = input("[Your question here]: ").rstrip()

        alt_count = 0
        while True:
            print("\nHow many answer alternatives should this question have?")
            print("Enter a number between 2 and 20")
            try:
                alt_count = int(input("Number of alternatives: ").strip())
                if 2 <= alt_count <= 20:
                    break
                else:
                    print("Please enter a value between 2 and 20.")
            except ValueError:
                print("Invalid integer.")

        alternatives = []
        for i in range(alt_count):
            alt_txt = input(f"Alternative {i+1}: ").rstrip()
            alternatives.append(alt_txt if alt_txt else f"Option {i+1}")

        is_critical = False
        print("\nSelect question type:")
        print("Standard is selected by default.")
        print("If you want to mark this question as critical, press c.")
        print("(Otherwise, press Enter to keep it as Standard)")
        choice_type = input("Choice: ").strip().lower()
        if choice_type == 'c':
            is_critical = True

        # Re-edit
        print("\nWould you like to re-edit anything before proceeding?")
        print("Press q  – Re-edit the security question")
        print("Press a  – Re-edit all answer alternatives")
        print("Press #  – Re-edit a single alternative (2..20)")
        print("(Or press Enter to continue)")
        while True:
            e_choice = input("Re-edit choice: ").strip().lower()
            if e_choice == '':
                # done
                break
            elif e_choice == 'q':
                question_text = input("\nRe-enter security question text:\n").rstrip()
                print("(Question updated.)\n")
            elif e_choice == 'a':
                new_all = []
                for i in range(alt_count):
                    new_a = input(f"Re-enter Alternative {i+1}: ").rstrip()
                    new_all.append(new_a if new_a else f"Option {i+1}")
                alternatives = new_all
                print("(Alternatives updated.)\n")
            else:
                # see if e_choice is a number
                try:
                    idx = int(e_choice)
                    if 2 <= idx <= alt_count:
                        new_val = input(f"Re-enter Alternative {idx}: ").rstrip()
                        alternatives[idx - 1] = new_val if new_val else f"Option {idx}"
                        print("(Alternative updated.)\n")
                    else:
                        print(f"Must be between 2 and {alt_count} if editing a single alternative.\n")
                except:
                    print("Unrecognized re-edit choice.\n")

        # Store question
        question_data = {
            "id": current_qnum,
            "text": question_text,
            "alternatives": alternatives,
            "is_critical": is_critical
        }
        questions.append(question_data)

        # Navigation
        print("\nNavigation options:")
        print("Press n  – Proceed to the next question")
        print("Press b  – Go back and revise the previous question")
        print("Press d  – Done (finish input)")
        print(f"(You must have at least 2 questions, you currently have {len(questions)}.)")

        nav = input("Choice: ").strip().lower()
        if nav == 'n':
            # proceed to next question => loop continues
            if len(questions) >= 100:
                print("You have reached the maximum of 100 questions. Finishing input now.")
                break
        elif nav == 'b':
            if len(questions) > 1:
                # remove the last question
                removed_q = questions.pop()
                prev_q = questions.pop()
                print("\nRevising the previous question...\n")
                # Let user do a minimal re-edit
                prev_q = quick_revise_question(prev_q)
                questions.append(prev_q)
                # restore the newest question that was removed, if needed
                questions.append(removed_q)
            else:
                print("(No previous question to revise.)")
        elif nav == 'd':
            if len(questions) < 2:
                print("You must have at least 2 questions. Continue adding more.")
                continue
            else:
                print("\n--- Manual input complete. ---\n")
                break
        else:
            print("Unrecognized choice; continuing.\n")

        if len(questions) >= 2 and nav == 'd':
            # user finished
            break

    # Show final summary
    print("Summary of your manually entered questions:\n")
    for qd in questions:
        i = qd["id"]
        qtype_str = "CRITICAL" if qd["is_critical"] else "STANDARD"
        print(f"[Question {i}] {qd['text']}")
        # label alternatives A, B, C...
        for idx, alt in enumerate(qd["alternatives"], 1):
            letter = chr(ord('A') + idx - 1)
            print(f"  {letter} {alt}")
        print(f"  Type: {qtype_str}\n")

    return questions


def quick_revise_question(qdict):
    """
    Minimal 'back' revision for one question. 
    Allows re-entering question text, re-entering alternatives, toggling critical, etc.
    """
    old_text = qdict["text"]
    old_alts = qdict["alternatives"]
    old_crit = qdict["is_critical"]
    alt_count = len(old_alts)

    print(f"Previous question text: {old_text}")
    print("Press q to change question text, a to re-edit all alternatives, c to toggle critical.\n"
          "(Press Enter=keep as-is)")
    sub = input("Choice: ").strip().lower()
    if sub == 'q':
        new_q = input("\nEnter new question text:\n").rstrip()
        qdict["text"] = new_q if new_q else old_text
        print("(Question text updated.)\n")
    elif sub == 'a':
        new_all = []
        for i in range(alt_count):
            new_a = input(f"Re-enter Alternative {i+1}: ").rstrip()
            new_all.append(new_a if new_a else f"Option {i+1}")
        qdict["alternatives"] = new_all
        print("(Alternatives updated.)\n")
    elif sub == 'c':
        qdict["is_critical"] = not old_crit
        print(f"(Critical toggled. Now => {qdict['is_critical']})\n")
    else:
        print("(No changes made to the previous question.)\n")

    return qdict


def prompt_save_decision():
    """
    After user is done with question input, ask if they want to save:
      Press j  – Save as both JSON and text file
      Press c  – Continue without saving
    """
    while True:
        print("\nWould you like to save your questions?")
        print("Press j  – Save as both JSON and text file")
        print("Press c  – Continue without saving")
        choice = input("Choice: ").strip().lower()
        if choice in ['j', 'c']:
            return choice
        else:
            print("Invalid choice.")


def save_questions(questions):
    """
    Saves question set to the next available user_questionsX.json and user_questionsX.txt
    in the current working directory, never overwriting existing files.
    JSON format:
    [
      {
        "id": 1,
        "text": "...",
        "alternatives": [...],
        "is_critical": ...
      },
      ...
    ]

    TXT format (human-readable):
    [Question i text]
    A [Alternative]
    B [Alternative]
    ...
    """
    base_json = "user_questions"
    base_txt = "user_questions"
    json_file = get_next_filename(base_json, "json")
    txt_file = get_next_filename(base_txt, "txt")

    # 1) Write JSON
    data_for_json = []
    for q in questions:
        # replicate the format specified (though we have 'is_critical', we can still store it)
        obj = {
            "id": q["id"],
            "text": q["text"],
            "alternatives": q["alternatives"]
        }
        data_for_json.append(obj)
    with open(json_file, "w", encoding="utf-8") as jf:
        json.dump(data_for_json, jf, indent=2)

    # 2) Write TXT
    with open(txt_file, "w", encoding="utf-8") as tf:
        for i, q in enumerate(questions, 1):
            tf.write(f"{q['text']}\n\n")
            # label alternatives A, B, C...
            for idx, alt in enumerate(q['alternatives'], 1):
                letter = chr(ord('A') + idx - 1)
                tf.write(f"{letter} {alt}\n")
            if i < len(questions):
                tf.write("\n")

    print(f"Saved questions to '{json_file}' and '{txt_file}' in the current directory.")


def get_next_filename(base_name, extension):
    """
    Finds the next available filename in the pattern:
      base_name.ext
      base_name2.ext
      base_name3.ext
      ...
    in the current working directory, never overwriting existing files.
    """
    cwd = Path.cwd()
    idx = 0
    while True:
        idx += 1
        if idx == 1:
            candidate = cwd / f"{base_name}.{extension}"
        else:
            candidate = cwd / f"{base_name}{idx}.{extension}"
        if not candidate.exists():
            return candidate


def check_required_files():
    needed_in_src = ["CipherForge.py", "example_questions25.json"]
    missing = []
    for f in needed_in_src:
        if not (SRC_DIR / f).exists():
            missing.append(f)

    modules_path = SRC_DIR / "modules"
    needed_in_modules = [
        "debug_utils.py",
        "input_utils.py",
        "log_processor.py",
        "security_utils.py",
        "split_utils.py",
        "SSS.py",
        "ui_utils.py"
    ]
    for f in needed_in_modules:
        if not (modules_path / f).exists():
            missing.append(f)

    if missing:
        log_error("Missing required files", None, {"missing": missing})
        print("ERROR - Missing files:", missing)
        sys.exit(1)


def prompt_argon2_parameters():
    print("\n--- Argon2id Parameter Setup ---")
    choice_ = input("Use (n) for normal defaults or (e) for custom edit? [n/e] ").strip().lower()
    if choice_ != 'e':
        print("Using DEFAULT Argon2id parameters: time_cost=3, memory_cost=65536, parallelism=4")
        input("Press ENTER to continue with these defaults...")
        return (3, 65536, 4)
    else:
        print("Enter custom Argon2id parameters:")
        tc = get_valid_int("time_cost (1..10)? ", 1, 10)
        mc = get_valid_int("memory_cost (8192..1048576)? ", 8192, 1048576)
        pl = get_valid_int("parallelism (1..32)? ", 1, 32)
        print(f"Using CUSTOM Argon2id parameters: time_cost={tc}, memory_cost={mc}, parallelism={pl}")
        return (tc, mc, pl)


def calc_qna_search_space(chosen):
    """
    Calculates how many total ways an attacker might attempt Q&A picks
    (assuming each question can have any non-empty subset of its alternatives).
    """
    import math
    total = 1
    for q in chosen:
        n_alts = len(q["alternatives"])
        ways = (1 << n_alts) - 1
        total *= ways
    return total


def estimate_argon2_time_ms(arg_time, arg_mem, arg_par):
    """
    For demonstration, assume ~0.05 ms per guess in a high-performance environment.
    """
    return 0.05


def convert_seconds_to_dhms(seconds):
    import math
    year_sec   = 365.25  * 24 * 3600
    month_sec  = 30.4375 * 24 * 3600
    day_sec    = 24 * 3600
    hour_sec   = 3600
    minute_sec = 60
    out = {
        "years":   0,
        "months":  0,
        "days":    0,
        "hours":   0,
        "minutes": 0,
        "seconds": 0.0
    }
    if seconds <= 0:
        return out
    y = int(seconds // year_sec)
    out["years"] = y
    seconds -= (y * year_sec)
    mo = int(seconds // month_sec)
    out["months"] = mo
    seconds -= (mo * month_sec)
    d = int(seconds // day_sec)
    out["days"] = d
    seconds -= (d * day_sec)
    h = int(seconds // hour_sec)
    out["hours"] = h
    seconds -= (h * hour_sec)
    m = int(seconds // minute_sec)
    out["minutes"] = m
    seconds -= (m * minute_sec)
    out["seconds"] = seconds
    return out


def print_estimated_bruteforce_times(chosen, arg_time, arg_mem, arg_par):
    import math
    search_space = calc_qna_search_space(chosen)
    if search_space < 1:
        search_space = 1
    single_guess_ms = estimate_argon2_time_ms(arg_time, arg_mem, arg_par)
    total_classical_ms = search_space * single_guess_ms
    total_quantum_ms   = math.sqrt(search_space) * single_guess_ms
    total_classical_sec = total_classical_ms / 1000.0
    total_quantum_sec   = total_quantum_ms   / 1000.0
    classical_breakdown = convert_seconds_to_dhms(total_classical_sec)
    quantum_breakdown   = convert_seconds_to_dhms(total_quantum_sec)

    print("\n--- Estimated Brute-Force Difficulty ---")
    print(f"Total Q&A search space: {search_space:,} possible guesses.")
    print(f"Single Argon2 guess time: ~{single_guess_ms:.3f} ms.")
    print("\n[CLASSICAL Attack] =>")
    print(f"  Years   : {classical_breakdown['years']}")
    print(f"  Months  : {classical_breakdown['months']}")
    print(f"  Days    : {classical_breakdown['days']}")
    print(f"  Hours   : {classical_breakdown['hours']}")
    print(f"  Minutes : {classical_breakdown['minutes']}")
    print(f"  Seconds : {classical_breakdown['seconds']:.2f}")

    print("\n[QUANTUM Speedup Attack] =>")
    print(f"  Years   : {quantum_breakdown['years']}")
    print(f"  Months  : {quantum_breakdown['months']}")
    print(f"  Days    : {quantum_breakdown['days']}")
    print(f"  Hours   : {quantum_breakdown['hours']}")
    print(f"  Minutes : {quantum_breakdown['minutes']}")
    print(f"  Seconds : {quantum_breakdown['seconds']:.2f}\n")


def main():
    try:
        # Start the existing flow only after user chooses "2" in the menu
        print("[INFO] Launching main.py...")

        ensure_debug_dir()
        check_required_files()
        log_debug("Starting program...", level="INFO")

        # 1) Load question data (unchanged from prior code)
        if not QUESTIONS_PATH.exists():
            msg_ = f"Error: question file not found: {QUESTIONS_PATH}"
            log_error(msg_)
            print(msg_)
            return
        try:
            with open(QUESTIONS_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
            empty_correct = 0
            for qd in data:
                if validate_question(qd):
                    from modules.security_utils import sanitize_input, normalize_text
                    qd["correct_answers"] = [
                        sanitize_input(normalize_text(ans)) for ans in qd.get("correct_answers", [])
                    ]
                    qd["alternatives"] = [
                        sanitize_input(normalize_text(alt)) for alt in qd["alternatives"]
                    ]
                    qd["qna_hash"] = hash_question_and_answers(qd)
                    if not qd["correct_answers"]:
                        empty_correct += 1
                        qd["correct_answers"] = qd["alternatives"][:]
                        log_debug(
                            f"Question '{qd['text']}' had empty 'correct_answers'. Now set them all as correct.",
                            level="INFO"
                        )
            valid_data = [q for q in data if validate_question(q)]
            if empty_correct > 0:
                print(
                    f"NOTICE: {empty_correct} question(s) had empty 'correct_answers'. "
                    "All alternatives for those are treated as correct.\n"
                )
        except Exception as e:
            log_exception(e, "Error loading question file")
            return
        if not valid_data:
            print("No valid questions found. Aborting.")
            return

        amt = get_valid_int(f"How many questions? (1..{len(valid_data)}): ", 1, len(valid_data))
        with chosen_lock:
            chosen = valid_data[:amt]

        # 2) arrow-select each question
        correct_cumulative = 0
        incorrect_cumulative = 0
        for i, qdict in enumerate(chosen, 1):
            picks, qtype = curses.wrapper(
                lambda s: arrow_select_clear_on_toggle(
                    s, i, qdict["text"], qdict["alternatives"],
                    pre_selected=qdict.get("user_answers"),
                    pre_qtype=1 if qdict.get("is_critical") else 0,
                    fixed_type=qdict.get("force_type")
                )
            )
            qdict["user_answers"] = picks
            qdict["is_critical"] = bool(qtype) if not qdict.get("force_type") \
                else (qdict["force_type"].upper() == "CRITICAL")

            c_local = 0
            i_local = 0
            cset_local = set(qdict.get("correct_answers", []))
            for alt_ in picks:
                if alt_ in cset_local:
                    c_local += 1
                else:
                    i_local += 1

            log_debug(
                f"Q{i}: text='{qdict['text']}' => user_picks={picks}, "
                f"correct_answers={list(cset_local)}, local_c={c_local}, local_i={i_local}",
                level="DEBUG"
            )
            correct_cumulative += c_local
            incorrect_cumulative += i_local
            print(f"[FEEDBACK] After Q{i}: +{c_local} correct, +{i_local} incorrect.")
            print(f"Total so far => correct={correct_cumulative}, incorrect={incorrect_cumulative}\n")

        while True:
            done = editing_menu(chosen)
            if done:
                break

        correct_map = []
        incorrect_map = []
        for idx, q in enumerate(chosen, 1):
            cset = set(q.get("correct_answers", []))
            picks_ = q["user_answers"]
            local_c = 0
            local_i = 0
            for alt in picks_:
                if alt in cset:
                    correct_map.append((q, alt))
                    local_c += 1
                else:
                    incorrect_map.append((q, alt))
                    local_i += 1
            log_debug(f"After re-edit Q{idx}: c={local_c}, i={local_i}", level="INFO")

        c_count = len(correct_map)
        i_count = len(incorrect_map)
        log_debug(f"FINAL TALLY => c_count={c_count}, i_count={i_count}", level="INFO")
        print(f"\nOverall Tally => Correct picks={c_count}, Incorrect={i_count}.\n")

        # must have >= 10 correct
        while True:
            if c_count < 10:
                if c_count == 0:
                    log_debug("0 picks => must re-edit or abort", level="INFO")
                    print("Zero correct picks => cannot proceed with Shamir’s Secret Sharing.")
                    print("(E => re-edit answers, N => abort)")
                    answer = input("Choice (E/N)? ").strip().upper()
                    if answer == 'E':
                        re_done = editing_menu(chosen)
                        if re_done:
                            correct_map.clear()
                            incorrect_map.clear()
                            for q_ in chosen:
                                cset_ = set(q_.get("correct_answers", []))
                                picks_ = q_["user_answers"]
                                for alt_ in picks_:
                                    if alt_ in cset_:
                                        correct_map.append((q_, alt_))
                                    else:
                                        incorrect_map.append((q_, alt_))
                            c_count = len(correct_map)
                            i_count = len(incorrect_map)
                            log_debug(f"After re-edit => c_count={c_count}, i_count={i_count}", level="INFO")
                            print(f"\nNEW Tally => Correct picks={c_count}, Incorrect={i_count}.\n")
                            continue
                    elif answer == 'N':
                        confirm = input("Are you sure you want to abort? (y/n): ").strip().lower()
                        if confirm.startswith('y'):
                            log_debug("User aborted at zero picks => exit now", level="INFO")
                            print("Aborting.")
                            return
                        else:
                            print("Returning to editing menu instead of abort.")
                            continue
                    else:
                        print("Invalid choice.\n")
                        continue
                else:
                    print("Fewer than 10 correct => re-edit or abort.")
                    answer = input("Choice (E/N)? ").strip().upper()
                    if answer == 'E':
                        re_done = editing_menu(chosen)
                        if re_done:
                            correct_map.clear()
                            incorrect_map.clear()
                            for q_ in chosen:
                                cset_ = set(q_.get("correct_answers", []))
                                picks_ = q_["user_answers"]
                                for alt_ in picks_:
                                    if alt_ in cset_:
                                        correct_map.append((q_, alt_))
                                    else:
                                        incorrect_map.append((q_, alt_))
                            c_count = len(correct_map)
                            i_count = len(incorrect_map)
                            log_debug(f"After re-edit => c_count={c_count}, i_count={i_count}", level="INFO")
                            print(f"\nNEW Tally => Correct picks={c_count}, Incorrect={i_count}.\n")
                            continue
                    elif answer == 'N':
                        confirm = input("Are you sure you want to abort? (y/n): ").strip().lower()
                        if confirm.startswith('y'):
                            log_debug("User aborted at <10 picks => exit now", level="INFO")
                            print("Aborting.")
                            return
                        else:
                            print("Returning to editing menu instead of abort.")
                            continue
                    else:
                        print("Invalid choice.\n")
                        continue
            else:
                break

        def get_threshold(low, high):
            while True:
                raw = input(f"Real threshold ({low}..{high}): ")
                try:
                    val = int(raw)
                    if val >= low and val <= high:
                        return val
                except:
                    pass
                print(f"Must be {low}..{high}.\n")

        r_thr = get_threshold(10, c_count)
        print(f"[INFO] Must pick >= {r_thr} correct picks to reconstruct real secret.\n")

        real_secret = get_nonempty_secret("Enter REAL secret: ")
        real_b64 = base64.b64encode(real_secret.encode()).decode()
        recommended_pad = max(128, len(real_b64) + 32)
        print(f"\nCustom PAD size? Press ENTER to use recommended={recommended_pad}.")
        try_pad = input(f"PAD must be >= {len(real_b64)}: ").strip()
        if try_pad:
            try:
                user_pad = int(try_pad)
                if user_pad < len(real_b64):
                    print(f"Provided pad < base64 secret length. Forcing {len(real_b64)} instead.\n")
                    user_pad = len(real_b64)
            except:
                print(f"Invalid, using recommended={recommended_pad}.\n")
                user_pad = recommended_pad
        else:
            user_pad = recommended_pad
        if user_pad < len(real_b64):
            user_pad = len(real_b64)
            print(f"Forced final pad to {user_pad}.\n")

        arg_time, arg_mem, arg_par = prompt_argon2_parameters()

        try:
            real_shares, dummy_shares = asyncio.run(
                split_secret_and_dummy(real_b64.encode(), c_count, i_count, r_thr, pad=user_pad)
            )
        except Exception as e:
            log_exception(e, "Error splitting secret")
            return

        def split_into_95_5(full_bytes: bytes):
            length = len(full_bytes)
            five_p = max(1, (length * 5) // 100)
            part5 = full_bytes[-five_p:]
            part95 = full_bytes[:-five_p]
            return (part95, part5)

        def ephemeral_encrypt(data: bytes) -> dict:
            ephemeral_pass = base64.b64encode(os.urandom(12)).decode()
            ephemeral_salt = os.urandom(16)
            ephemeral_key, ephemeral_salt_used = derive_or_recover_key(
                ephemeral_pass,
                ephemeral_salt,
                ephemeral=True,
                time_cost=arg_time,
                memory_cost=arg_mem,
                parallelism=arg_par
            )
            alg_options = ["chacha20poly1305", "aes256gcm"]
            chosen_alg = choice(alg_options)
            if chosen_alg == "chacha20poly1305":
                enc_obj = encrypt_chacha20poly1305(data, ephemeral_key,
                                                   ephemeral_pass=ephemeral_pass,
                                                   ephemeral_salt=ephemeral_salt_used)
            else:
                enc_obj = encrypt_aes256gcm(data, ephemeral_key,
                                            ephemeral_pass=ephemeral_pass,
                                            ephemeral_salt=ephemeral_salt_used)
            enc_obj["ephemeral_password"] = ephemeral_pass
            enc_obj["ephemeral_salt_b64"] = base64.b64encode(ephemeral_salt_used).decode()
            enc_obj["algorithm"] = chosen_alg
            return enc_obj

        std_correct = []
        crit_correct = []
        for (q, alt) in correct_map:
            if q["is_critical"]:
                crit_correct.append((q, alt))
            else:
                std_correct.append((q, alt))
        std_incorrect = []
        crit_incorrect = []
        for (q, alt) in incorrect_map:
            if q["is_critical"]:
                crit_incorrect.append((q, alt))
            else:
                std_incorrect.append((q, alt))
        total_shares = len(real_shares)

        if i_count == 0:
            used = min(c_count, total_shares)
            for i in range(used):
                share = real_shares[i]
                enc_full = ephemeral_encrypt(share)
                (q_s, alt_s) = correct_map[i]
                q_s.setdefault("answer_shares", {})
                q_s["answer_shares"][alt_s] = {
                    "is_real": True,
                    "which_part": "100%",
                    "enc_data": enc_full,
                    "hash_": hash_share(share)
                }
                for j in range(len(share)):
                    share[j] = 0
        else:
            if len(crit_correct) <= 1:
                used_std = min(len(std_correct), total_shares)
                leftover_index = 0
                for i in range(used_std):
                    share = real_shares[i]
                    enc_full = ephemeral_encrypt(share)
                    (q_s, alt_s) = std_correct[i]
                    q_s.setdefault("answer_shares", {})
                    q_s["answer_shares"][alt_s] = {
                        "is_real": True,
                        "which_part": "100%",
                        "enc_data": enc_full,
                        "hash_": hash_share(share)
                    }
                    for j in range(len(share)):
                        share[j] = 0
                leftover_index = used_std
                used_crit = min(len(crit_correct), total_shares - leftover_index)
                for i in range(used_crit):
                    share = real_shares[leftover_index]
                    leftover_index += 1
                    enc_full = ephemeral_encrypt(share)
                    (q_c, alt_c) = crit_correct[i]
                    q_c.setdefault("answer_shares", {})
                    q_c["answer_shares"][alt_c] = {
                        "is_real": True,
                        "which_part": "100%",
                        "enc_data": enc_full,
                        "hash_": hash_share(share)
                    }
                    for j in range(len(share)):
                        share[j] = 0

                used_std_dummy = min(len(std_incorrect), len(dummy_shares))
                for i in range(used_std_dummy):
                    share = dummy_shares[i]
                    enc_full = ephemeral_encrypt(share)
                    (q_s, alt_s) = std_incorrect[i]
                    q_s.setdefault("answer_shares", {})
                    q_s["answer_shares"][alt_s] = {
                        "is_real": False,
                        "which_part": "100%",
                        "enc_data": enc_full,
                        "hash_": hash_share(share)
                    }
                    for j in range(len(share)):
                        share[j] = 0
                leftover_dummy_index = used_std_dummy
                used_crit_dummy = min(len(crit_incorrect), len(dummy_shares) - leftover_dummy_index)
                for i in range(used_crit_dummy):
                    share = dummy_shares[leftover_dummy_index]
                    leftover_dummy_index += 1
                    enc_full = ephemeral_encrypt(share)
                    (q_c, alt_c) = crit_incorrect[i]
                    q_c.setdefault("answer_shares", {})
                    q_c["answer_shares"][alt_c] = {
                        "is_real": False,
                        "which_part": "100%",
                        "enc_data": enc_full,
                        "hash_": hash_share(share)
                    }
                    for j in range(len(share)):
                        share[j] = 0
            else:
                used_pairs = min(len(std_correct), len(crit_correct), total_shares)
                for i in range(used_pairs):
                    share = real_shares[i]
                    part95, part5 = split_into_95_5(share)
                    (q_s, alt_s) = std_correct[i]
                    enc_95 = ephemeral_encrypt(part95)
                    q_s.setdefault("answer_shares", {})
                    q_s["answer_shares"][alt_s] = {
                        "is_real": True,
                        "which_part": "95%",
                        "enc_data": enc_95,
                        "hash_": hash_share(share)
                    }
                    (q_c, alt_c) = crit_correct[i]
                    enc_5 = ephemeral_encrypt(part5)
                    q_c.setdefault("answer_shares", {})
                    q_c["answer_shares"][alt_c] = {
                        "is_real": True,
                        "which_part": "5%",
                        "enc_data": enc_5,
                        "hash_": hash_share(share)
                    }
                    for j in range(len(share)):
                        share[j] = 0

                leftover_index = used_pairs
                leftover_std = std_correct[used_pairs:]
                leftover_crit = crit_correct[used_pairs:]
                for (q_s, alt_s) in leftover_std:
                    if leftover_index >= total_shares:
                        break
                    share = real_shares[leftover_index]
                    leftover_index += 1
                    enc_full = ephemeral_encrypt(share)
                    q_s.setdefault("answer_shares", {})
                    q_s["answer_shares"][alt_s] = {
                        "is_real": True,
                        "which_part": "100%",
                        "enc_data": enc_full,
                        "hash_": hash_share(share)
                    }
                    for j in range(len(share)):
                        share[j] = 0
                for (q_c, alt_c) in leftover_crit:
                    if leftover_index >= total_shares:
                        break
                    share = real_shares[leftover_index]
                    leftover_index += 1
                    enc_full = ephemeral_encrypt(share)
                    q_c.setdefault("answer_shares", {})
                    q_c["answer_shares"][alt_c] = {
                        "is_real": True,
                        "which_part": "100%",
                        "enc_data": enc_full,
                        "hash_": hash_share(share)
                    }
                    for j in range(len(share)):
                        share[j] = 0

                used_pairs_dummy = min(len(std_incorrect), len(crit_incorrect), len(dummy_shares))
                for i in range(used_pairs_dummy):
                    share = dummy_shares[i]
                    part95, part5 = split_into_95_5(share)
                    (q_s, alt_s) = std_incorrect[i]
                    enc_95 = ephemeral_encrypt(part95)
                    q_s.setdefault("answer_shares", {})
                    q_s["answer_shares"][alt_s] = {
                        "is_real": False,
                        "which_part": "95%",
                        "enc_data": enc_95,
                        "hash_": hash_share(share)
                    }
                    (q_c, alt_c) = crit_incorrect[i]
                    enc_5 = ephemeral_encrypt(part5)
                    q_c.setdefault("answer_shares", {})
                    q_c["answer_shares"][alt_c] = {
                        "is_real": False,
                        "which_part": "5%",
                        "enc_data": enc_5,
                        "hash_": hash_share(share)
                    }
                    for j in range(len(share)):
                        share[j] = 0
                leftover_dummy_index = used_pairs_dummy
                leftover_std_incorrect = std_incorrect[used_pairs_dummy:]
                leftover_crit_incorrect = crit_incorrect[used_pairs_dummy:]
                for (q_s, alt_s) in leftover_std_incorrect:
                    if leftover_dummy_index >= len(dummy_shares):
                        break
                    share = dummy_shares[leftover_dummy_index]
                    leftover_dummy_index += 1
                    enc_full = ephemeral_encrypt(share)
                    q_s.setdefault("answer_shares", {})
                    q_s["answer_shares"][alt_s] = {
                        "is_real": False,
                        "which_part": "100%",
                        "enc_data": enc_full,
                        "hash_": hash_share(share)
                    }
                    for j in range(len(share)):
                        share[j] = 0
                for (q_c, alt_c) in leftover_crit_incorrect:
                    if leftover_dummy_index >= len(dummy_shares):
                        break
                    share = dummy_shares[leftover_dummy_index]
                    leftover_dummy_index += 1
                    enc_full = ephemeral_encrypt(share)
                    q_c.setdefault("answer_shares", {})
                    q_c["answer_shares"][alt_c] = {
                        "is_real": False,
                        "which_part": "100%",
                        "enc_data": enc_full,
                        "hash_": hash_share(share)
                    }
                    for j in range(len(share)):
                        share[j] = 0

        unique_real_hashes = set()
        for q_ in chosen:
            ashares_ = q_.get("answer_shares", {})
            for alt_k, info_k in ashares_.items():
                if info_k["is_real"]:
                    unique_real_hashes.add(info_k["hash_"])
        assigned_real_count = len(unique_real_hashes)
        if r_thr > assigned_real_count:
            print(f"\nNOTICE: Only {assigned_real_count} real shares assigned, "
                  f"but threshold={r_thr}. Adjusting threshold down.")
            r_thr = assigned_real_count
            print(f"Threshold set to {r_thr} so reconstruction remains possible.\n")
            log_debug(f"Threshold forced to {r_thr} due to assigned_real_count={assigned_real_count}",
                      level="INFO")

        print("\n--- Final Answering Phase ---\n")
        for i, q in enumerate(chosen, 1):
            picks2 = curses.wrapper(
                lambda st: arrow_select_no_toggle(
                    st, i, q["text"], q["alternatives"],
                    pre_selected=q.get("user_answers")
                )
            )
            q["user_answers"] = picks2

        while True:
            result = final_edit_menu(chosen)
            if result == 'G':
                log_debug("User finalize => combine secrets now.", level="INFO")
                break
            elif result == 'N':
                print("Aborted. Exiting.")
                return

        partials_map = {}
        for q in chosen:
            for alt in q["user_answers"]:
                info = q.get("answer_shares", {}).get(alt)
                if not info:
                    continue
                enc_data = info["enc_data"]
                ephemeral_pass = enc_data.get("ephemeral_password")
                ephemeral_salt_b64 = enc_data.get("ephemeral_salt_b64")
                if not ephemeral_pass or not ephemeral_salt_b64:
                    continue
                ephemeral_salt = base64.b64decode(ephemeral_salt_b64)
                ephemeral_key, _ = derive_or_recover_key(
                    ephemeral_pass,
                    ephemeral_salt,
                    ephemeral=True,
                    time_cost=arg_time,
                    memory_cost=arg_mem,
                    parallelism=arg_par
                )
                if enc_data.get("algorithm") == "chacha20poly1305":
                    dec_pt = decrypt_chacha20poly1305(enc_data, ephemeral_key)
                else:
                    dec_pt = decrypt_aes256gcm(enc_data, ephemeral_key)

                h = info["hash_"]
                is_real = info["is_real"]
                wpart = info["which_part"]
                partials_map.setdefault(h, {"is_real": is_real, "95%": None, "5%": None, "100%": None})
                if wpart in ("95%", "5%"):
                    if partials_map[h][wpart] is None:
                        partials_map[h][wpart] = dec_pt
                else:
                    partials_map[h]["100%"] = dec_pt

        recovered_shares = []
        for h, entry in partials_map.items():
            if not entry["is_real"]:
                continue
            if entry["100%"] is not None:
                full_share = entry["100%"]
                if verify_share_hash(full_share, h):
                    recovered_shares.append(full_share)
            else:
                if entry["95%"] is not None and entry["5%"] is not None:
                    full_share = entry["95%"] + entry["5%"]
                    if verify_share_hash(full_share, h):
                        recovered_shares.append(full_share)

        if len(recovered_shares) < r_thr:
            print(f"Not enough real partial shares => reconstruct fail. "
                  f"Found={len(recovered_shares)}, threshold={r_thr}")
            return

        final_picks = recovered_shares[:r_thr]
        reconstructed_real = None
        try:
            combined = asyncio.run(sss_combine(final_picks))
            try:
                dec_real = base64.b64decode(combined).decode()
                reconstructed_real = dec_real
            except Exception as e:
                reconstructed_real = f"<Decode error: {e}>"
        except Exception as e:
            log_exception(e, "Combine fail")

        print("\n--- FINAL RECONSTRUCTION RESULTS ---\n")
        if reconstructed_real and not reconstructed_real.startswith("<"):
            print(f"REAL SECRET recovered: {reconstructed_real}\n")
        else:
            print("Secret not recoverable.\n")

        print("""
--- Steps to manually reconstruct (if not done above) ---
1. Identify correct standard & critical picks and ephemeral-encrypted partials.
2. Decrypt each 95% chunk + 5% chunk, or single 100% chunk.
3. Provide enough real shares => sss_combine => base64-decode final secret.
""")

        append_recovery_guide()
        log_debug("Done with main program.", level="INFO")
        print_estimated_bruteforce_times(chosen, arg_time, arg_mem, arg_par)

    except Exception as exc_main:
        log_exception(exc_main, "Fatal error in main()")
        print(f"FATAL ERROR: {exc_main}")
        sys.exit(1)


if __name__ == "__main__":
    # 1) Show the startup menu BEFORE any logs/notices.
    show_start_menu()
    # 2) Proceed to main() only if user presses "2".
    main()

################################################################################
# END OF FILE: "main.py"
################################################################################
